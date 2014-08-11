#if __APPLE__
# include "TargetConditionals.h"
# if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>

#include <gameplay.h>

#include "InAppPurchase.h"

#define ProductsLoadedNotification @"ProductsLoaded"
#define ProductPurchasedNotification @"ProductPurchased"
#define ProductPurchaseFailedNotification @"ProductPurchaseFailed"

@interface InAppPurchaseiOS : NSObject<SKProductsRequestDelegate, SKPaymentTransactionObserver>
{
    NSSet *m_productIdentifiers;
    NSArray *m_products;
    NSMutableSet *m_purchasedProducts;
    SKProductsRequest *m_request;
    NSNumberFormatter *m_priceFormatter;
}

@property (nonatomic, retain) NSSet *productIdentifiers;
@property (retain) NSArray *products;
@property (retain) NSMutableSet *purchasedProducts;
@property (retain) SKProductsRequest *request;

- (id) init;
- (void) setProductIdentifiers : (NSSet *) productIdentifiers;
- (void) setProductIdentifiersWithURL : (NSURL *) url;
- (void) setProductIdentifiersWithURL : (NSURL *) url : (NSSet *) staticProductIdentifiers;
- (void) requestProducts;
- (bool) canMakePayments;
- (void) buyProductWithIdentifier : (NSString *) productIdentifier;
- (void) buyProductWithItem : (const gameplay::InAppPurchaseItem &) product;
- (void) buyProduct : (SKProduct *) product;
- (bool) isProductPurchasedWithIdentifier : (NSString *) productIdentifier;
- (bool) isProductPurchasedWithItem : (const gameplay::InAppPurchaseItem &) product;
- (bool) isProductPurchased : (SKProduct *) product;
- (void) downloadImageForProduct : (NSString *) productIdentifier;

+ (InAppPurchaseiOS *) GetInstance;

@end

@implementation InAppPurchaseiOS

@synthesize productIdentifiers = m_productIdentifiers;
@synthesize products = m_products;
@synthesize purchasedProducts = m_purchasedProducts;
@synthesize request = m_request;

- (id) init
{
    if ((self = [super init]))
    {
        m_priceFormatter = [[NSNumberFormatter alloc] init];
        [m_priceFormatter setFormatterBehavior : NSNumberFormatterBehavior10_4];
        [m_priceFormatter setNumberStyle : NSNumberFormatterCurrencyStyle];
    }
    return self;
}

- (void) setProductIdentifiers : (NSSet *) productIdentifiers
{
    if (m_productIdentifiers)
    {
        m_products = nil;
        m_request = nil;
        m_productIdentifiers = nil;
        m_purchasedProducts = nil;
    }
    m_productIdentifiers = [productIdentifiers copy];
    std::vector<std::string> productsIdentifiers;
    NSMutableSet *purchasedProducts = [NSMutableSet set];
    for (NSString *productIdentifier in m_productIdentifiers)
    {
        productsIdentifiers.push_back([productIdentifier UTF8String]);
        BOOL productPurchased = [[NSUserDefaults standardUserDefaults] boolForKey : productIdentifier];
        if (productPurchased)
        {
            [purchasedProducts addObject : productIdentifier];
        }
    }
    self.purchasedProducts = purchasedProducts;
    gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
    the_inAppPurchaseWrapper.getProducts().clear();
    const std::vector<gameplay::InAppPurchaseCallback *> &callbacks = the_inAppPurchaseWrapper.getCallbacks();
    for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = callbacks.begin(); it != callbacks.end(); ++it)
    {
        (*it)->productsIdentifiersRetrieved(productsIdentifiers);
    }
}

- (void) setProductIdentifiersWithURL : (NSURL *) url
{
    [self setProductIdentifiersWithURL : url : [NSSet set]];
}

- (void) setProductIdentifiersWithURL : (NSURL *) url : (NSSet *) staticProductIdentifiers
{
    dispatch_queue_t main_queue = dispatch_get_main_queue();
    dispatch_queue_t global_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(global_queue, ^
                   {
                       NSMutableSet *set = [NSMutableSet set];
                       for (NSString *productIdentifier in staticProductIdentifiers)
                       {
                           [set addObject : productIdentifier];
                       }
                       NSError *error;
                       NSData *data = [NSData dataWithContentsOfURL : url options : kNilOptions error : &error];
                       if (data)
                       {
                           NSArray *productIdentifiers = [NSJSONSerialization JSONObjectWithData : data options : kNilOptions error : &error];
                           if (productIdentifiers)
                           {
                               for (NSString *productIdentifier in productIdentifiers)
                               {
                                   [set addObject : productIdentifier];
                               }
                           }
                           else
                           {
                               NSLog(@"Error while retrieving JSON data from url %@: %@", [url lastPathComponent], error);
                           }
                       }
                       else
                       {
                           NSLog(@"Error while retrieving content from url %@: %@", [url lastPathComponent], error);
                       }
                       dispatch_async(main_queue, ^
                                      {
                                          [self setProductIdentifiers : set];
                                      });
                   });
}

- (bool) canMakePayments
{
    return [SKPaymentQueue canMakePayments];
}

- (void) requestProducts
{
    m_request = [[SKProductsRequest alloc] initWithProductIdentifiers : m_productIdentifiers];
    m_request.delegate = self;
    [m_request start];
}

- (void) downloadImageForProduct : (NSString *) productIdentifier
{
    dispatch_queue_t main_queue = dispatch_get_main_queue();
    dispatch_queue_t global_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(global_queue, ^
                   {
                       NSString *imageName = @"__bundle_image.png";
                       NSString *directory = [self downloadContentPathForProductID : productIdentifier];
                       NSString *fullPath = [directory stringByAppendingPathComponent : imageName];
                       // Remove the "true" if you want to cache the image. The problem is that if the bundle is updated and its image is changed, we would still have the previous image. We have to introduce a notion of versioning in the image name to do efficiently.
                       if (true || [[NSFileManager defaultManager] fileExistsAtPath : fullPath] == NO)
                       {
                           NSString *itunesAPIUrl = @"http://itunes.apple.com/lookup?bundleId=";
                           NSString *requestURL = [itunesAPIUrl stringByAppendingString : productIdentifier];
                           NSURL *url = [NSURL URLWithString : [requestURL stringByAddingPercentEscapesUsingEncoding : NSUTF8StringEncoding]];
                           NSError *error;
                           NSData *data = [NSData dataWithContentsOfURL : url options : kNilOptions error : &error];
                           if (data)
                           {
                               NSDictionary *json = [NSJSONSerialization JSONObjectWithData : data options : kNilOptions error : &error];
                               if (json)
                               {
                                   NSString *numberOfResults;
                                   if ((numberOfResults = [json objectForKey : @"resultCount"]) && [numberOfResults integerValue] >= 1)
                                   {
                                       NSDictionary *firstResult =[[json objectForKey : @"results"] objectAtIndex : 0];
                                       if ((requestURL = [firstResult objectForKey : @"artworkUrl60"]))
                                       {
                                           url = [NSURL URLWithString : [requestURL stringByAddingPercentEscapesUsingEncoding : NSUTF8StringEncoding]];
                                           data = [NSData dataWithContentsOfURL : url options : kNilOptions error : &error];
                                           if (data)
                                           {
                                               data = [NSData dataWithData : UIImagePNGRepresentation([UIImage imageWithData : data])];
                                           }
                                           if (data)
                                           {
                                               if ([data writeToFile : fullPath options : kNilOptions error : &error] == NO)
                                               {
                                                   NSLog(@"Impossible to create %@ file: %@", fullPath, error);
                                               }
                                           }
                                           else
                                           {
                                               NSLog(@"Error while retrieving image from url %@ for bundle %@", [url lastPathComponent], productIdentifier);
                                           }
                                       }
                                       else
                                       {
                                           NSLog(@"Error while retrieving image URL for bundle %@", productIdentifier);
                                       }
                                   }
                                   else
                                   {
                                       NSLog(@"Error while retrieving image for bundle %@: No image found", productIdentifier);
                                   }
                               }
                               else
                               {
                                   NSLog(@"Error while retrieving JSON data from url %@: %@", [url lastPathComponent], error);
                               }
                           }
                           else
                           {
                               NSLog(@"Error while retrieving image for bundle %@: %@", productIdentifier, error);
                           }
                       }
                       if ([[NSFileManager defaultManager] fileExistsAtPath : fullPath])
                       {
                           
                           gameplay::Image *image = gameplay::Image::create([fullPath UTF8String]);
                           if (image)
                           {
                               dispatch_async(main_queue, ^
                                              {
                                                  gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
                                                  gameplay::InAppPurchaseItem &item = the_inAppPurchaseWrapper.getProducts()[[productIdentifier UTF8String]];
                                                  item.imagePreviewPath = [fullPath UTF8String];
                                                  const std::vector<gameplay::InAppPurchaseCallback *> &callbacks = the_inAppPurchaseWrapper.getCallbacks();
                                                  for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = callbacks.begin(); it != callbacks.end(); ++it)
                                                  {
                                                      (*it)->imagePreviewLoaded(item);
                                                  }
                                              });
                           }
                       }
                   });
}

- (void) productsRequest : (SKProductsRequest *) request didReceiveResponse : (SKProductsResponse *) response
{
    self.products = [response.products copy];
    self.request = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName : ProductsLoadedNotification object : m_products];
    std::map<std::string, gameplay::InAppPurchaseItem> &products = gameplay::InAppPurchaseWrapper::GetUniqueInstance().getProducts();
    for (SKProduct *product in m_products)
    {
        gameplay::InAppPurchaseItem item;
        item.downloable = product.downloadable;
        item.localizedDescription = [product.localizedDescription UTF8String];
        item.localizedTitle = [product.localizedTitle UTF8String];
        [m_priceFormatter setLocale : product.priceLocale];
        NSString *currencyCode = [product.priceLocale objectForKey : NSLocaleCurrencyCode];
        [m_priceFormatter setCurrencySymbol : currencyCode];
        item.price = [[m_priceFormatter stringFromNumber : product.price] UTF8String];
        item.productIdentifier = [product.productIdentifier UTF8String];
        products[item.productIdentifier] = item;
        [self downloadImageForProduct : product.productIdentifier];
    }
    const std::vector<gameplay::InAppPurchaseCallback *> &callbacks = gameplay::InAppPurchaseWrapper::GetUniqueInstance().getCallbacks();
    for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = callbacks.begin(); it != callbacks.end(); ++it)
    {
        (*it)->productsRetrieved(products);
    }
}

- (void) productsLoaded : (NSNotification *) notification
{
    [NSObject cancelPreviousPerformRequestsWithTarget : self];
}

- (void) recordTransaction : (SKPaymentTransaction *) transaction
{
    NSData *newReceipt = transaction.transactionReceipt;
    NSArray *receipts = [[NSUserDefaults standardUserDefaults] arrayForKey : @"receipts"];
    if (!receipts)
    {
        [[NSUserDefaults standardUserDefaults] setObject : @[newReceipt] forKey : @"receipts"];
    }
    else
    {
        NSArray *updatedReceipts = [receipts arrayByAddingObject : newReceipt];
        [[NSUserDefaults standardUserDefaults] setObject : updatedReceipts forKey : @"receipts"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) provideContent : (NSString *) productIdentifier
{
    [[NSUserDefaults standardUserDefaults] setBool : TRUE forKey : productIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [m_purchasedProducts addObject : productIdentifier];
    [[NSNotificationCenter defaultCenter] postNotificationName : ProductPurchasedNotification object : productIdentifier];
}

- (void) completeTransaction : (SKPaymentTransaction *) transaction
{
    [self recordTransaction : transaction];
    [self provideContent : transaction.payment.productIdentifier];
    if (transaction.downloads)
    {
        [[SKPaymentQueue defaultQueue] startDownloads : transaction.downloads];
    }
    else
    {
        [[SKPaymentQueue defaultQueue] finishTransaction : transaction];
    }
}

- (void) restoreTransaction : (SKPaymentTransaction *) transaction
{
    [self recordTransaction : transaction];
    [self provideContent : transaction.originalTransaction.payment.productIdentifier];
    if (transaction.downloads)
    {
        [[SKPaymentQueue defaultQueue] startDownloads : transaction.downloads];
    }
    else
    {
        [[SKPaymentQueue defaultQueue] finishTransaction : transaction];
    }
}

- (void) failedTransaction : (SKPaymentTransaction *) transaction
{
    if (transaction.error.code != SKErrorPaymentCancelled)
    {
        NSLog(@"Transaction error: %@", transaction.error.localizedDescription);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName : ProductPurchaseFailedNotification object : transaction];
    [[SKPaymentQueue defaultQueue] finishTransaction : transaction];
}

- (void) paymentQueue : (SKPaymentQueue *) queue updatedTransactions : (NSArray *) transactions
{
    for (SKPaymentTransaction *transaction in transactions)
    {
        switch (transaction.transactionState)
        {
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction : transaction];
                break;
            case SKPaymentTransactionStateFailed:
                [self failedTransaction : transaction];
                break;
            case SKPaymentTransactionStateRestored:
                [self restoreTransaction : transaction];
                break;
            default:
                break;
        }
    }
}

- (NSString *) NSTimeIntervalToNSString : (NSTimeInterval) time
{
    NSInteger integerTime = (NSInteger) time;
    NSInteger seconds = integerTime % 60;
    NSInteger minutes = (integerTime / 60) % 60;
    NSInteger hours = (integerTime / 3600);
    return [NSString stringWithFormat : @"%02ld:%02ld:%02ld", (long) hours, (long) minutes, (long) seconds];
}

- (gameplay::InAppPurchaseContent) SKDownloadToInAppPurchaseContent : (SKDownload *) download
{
    gameplay::InAppPurchaseContent content;
    content.contentIdentifier = [download.contentIdentifier UTF8String];
    content.contentLength = download.contentLength;
    content.contentVersion = [download.contentVersion UTF8String];
    content.progress = download.progress;
    content.timeRemaining = [[self NSTimeIntervalToNSString : download.timeRemaining] UTF8String];
    return content;
}

- (BOOL) addSkipBackupAttributeToItemAtURL : (NSURL *) url
{
    assert([[NSFileManager defaultManager] fileExistsAtPath : [url path]]);
    NSError *error = nil;
    BOOL success = [url setResourceValue : [NSNumber numberWithBool : YES] forKey : NSURLIsExcludedFromBackupKey error : &error];
    if (!success)
    {
        NSLog(@"Error excluding %@ from backup %@", [url lastPathComponent], error);
    }
    return success;
}

- (void) contentDownloading : (SKDownload *) download
{
    const std::vector<gameplay::InAppPurchaseCallback *> &callbacks = gameplay::InAppPurchaseWrapper::GetUniqueInstance().getCallbacks();
    gameplay::InAppPurchaseContent content = [self SKDownloadToInAppPurchaseContent : download];
    if (content.progress != 0.0f)
    {
        for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = callbacks.begin(); it != callbacks.end(); ++it)
        {
            (*it)->productDownloading(content);
        }
    }
}

- (NSString *) downloableContentPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [paths objectAtIndex : 0];
    directory = [directory stringByAppendingPathComponent : @"Downloads"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath : directory] == NO)
    {
        NSError *error = nil;
        if ([fileManager createDirectoryAtPath : directory withIntermediateDirectories : YES attributes : nil error : &error] == NO)
        {
            NSLog(@"Unable to create directory: %@", error);
        }
        NSURL *url = [NSURL fileURLWithPath : directory];
        if ([url setResourceValue : [NSNumber numberWithBool : YES] forKey : NSURLIsExcludedFromBackupKey error : &error] == NO)
        {
            NSLog(@"Unable to exclude directory from backup: %@", error);
        }
    }
    return directory;
}

- (NSString *) downloadContentPathForProductID : (NSString *) productIdentifier
{
    NSString *directory = [self downloableContentPath];
    directory = [directory stringByAppendingPathComponent : productIdentifier];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath : directory] == NO)
    {
        NSError *error = nil;
        if ([fileManager createDirectoryAtPath : directory withIntermediateDirectories : YES attributes : nil error : &error] == NO)
        {
            NSLog(@"Unable to create directory: %@", error);
        }
        NSURL *url = [NSURL fileURLWithPath : directory];
        if ([url setResourceValue : [NSNumber numberWithBool : YES] forKey : NSURLIsExcludedFromBackupKey error : &error] == NO)
        {
            NSLog(@"Unable to exclude directory from backup: %@", error);
        }
    }
    return directory;
}

- (void) contentDownloaded : (SKDownload *) download
{
    [[SKPaymentQueue defaultQueue] finishTransaction : download.transaction];
    gameplay::InAppPurchaseContent content = [self SKDownloadToInAppPurchaseContent : download];
    NSString *path = [download.contentURL path];
    path = [path stringByAppendingPathComponent : @"Contents"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath : path error : &error];
    NSString *directory = [self downloadContentPathForProductID : download.contentIdentifier];
    content.contentDirectory = [directory UTF8String];
    for (NSString *file in files)
    {
        NSString *fullPathSrc = [path stringByAppendingPathComponent : file];
        NSString *fullPathDst = [directory stringByAppendingPathComponent : file];
        [fileManager removeItemAtPath : fullPathDst error : &error];
        if ([fileManager moveItemAtPath : fullPathSrc toPath : fullPathDst error : &error] == NO)
        {
            NSLog(@"Unable to move item: %@", error);
            content.contentFilesPath.push_back([fullPathSrc UTF8String]);
        }
        else
        {
            content.contentFilesPath.push_back([fullPathDst UTF8String]);
        }
    }    
    const std::vector<gameplay::InAppPurchaseCallback *> &callbacks = gameplay::InAppPurchaseWrapper::GetUniqueInstance().getCallbacks();
    for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = callbacks.begin(); it != callbacks.end(); ++it)
    {
        (*it)->productDownloaded(content);
    }
}

- (void) paymentQueue : (SKPaymentQueue *) queue updatedDownloads : (NSArray *) downloads
{
    for (SKDownload *download in downloads)
    {
        switch (download.downloadState)
        {
            case SKDownloadStateActive:
                [self contentDownloading : download];
                break;
            case SKDownloadStateFinished:
                [self contentDownloaded : download];
                break;
            default:
                break;
        }
    }
}

- (void) buyProductWithIdentifier : (NSString *) productIdentifier
{
    for (SKProduct *skProduct in m_products)
    {
        if (std::string([productIdentifier UTF8String]) == std::string([skProduct.productIdentifier UTF8String]))
        {
            [self buyProduct : skProduct];
        }
    }
}

- (void) buyProductWithItem : (const gameplay::InAppPurchaseItem &) product
{
    for (SKProduct *skProduct in m_products)
    {
        if (product.productIdentifier == std::string([skProduct.productIdentifier UTF8String]))
        {
            [self buyProduct : skProduct];
        }
    }
}

- (void) buyProduct : (SKProduct *) product
{
    SKPayment *payment = [SKPayment paymentWithProduct : product];
    [[SKPaymentQueue defaultQueue] addPayment : payment];
}

- (bool) isProductPurchasedWithIdentifier : (NSString *) productIdentifier
{
    for (SKProduct *skProduct in m_products)
    {
        if (std::string([productIdentifier UTF8String]) == std::string([skProduct.productIdentifier UTF8String]))
        {
            return [self isProductPurchased : skProduct];
        }
    }
    return false;
}

- (bool) isProductPurchasedWithItem : (const gameplay::InAppPurchaseItem &) product
{
    for (SKProduct *skProduct in m_products)
    {
        if (product.productIdentifier == std::string([skProduct.productIdentifier UTF8String]))
        {
            return [self isProductPurchased : skProduct];
        }
    }
    return false;
}

- (bool) isProductPurchased : (SKProduct *) product
{
    return [m_purchasedProducts containsObject : product.productIdentifier];
}

+ (InAppPurchaseiOS *) GetInstance
{
    static InAppPurchaseiOS *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^
                  {
                      instance = [[self alloc] init];
                      [[SKPaymentQueue defaultQueue] addTransactionObserver : instance];
                      [instance downloadImageForProduct : @"com.6l6interactive.Tree-Of-Dreams"];
                  });
    return instance;
}

@end

namespace gameplay
{
    void InAppPurchaseWrapper::initializeProduct(const std::vector<std::string> &productIdentifiers) const
    {
        NSMutableSet *staticProductIdentifiers = [NSMutableSet set];
        for (std::vector<std::string>::const_iterator it = productIdentifiers.begin(); it != productIdentifiers.end(); ++it)
        {
            [staticProductIdentifiers addObject : [NSString stringWithCString : it->c_str() encoding : [NSString defaultCStringEncoding]]];
        }
        [[InAppPurchaseiOS GetInstance] setProductIdentifiers : staticProductIdentifiers];
    }
    
    void InAppPurchaseWrapper::initializeProduct(const std::string &url) const
    {
        NSString *NSServerURL = [NSString stringWithCString : url.c_str() encoding : [NSString defaultCStringEncoding]];
        NSURL *serverURL = [NSURL URLWithString : [NSServerURL stringByAddingPercentEscapesUsingEncoding : NSUTF8StringEncoding]];
        [[InAppPurchaseiOS GetInstance] setProductIdentifiersWithURL : serverURL];
    }
    
    void InAppPurchaseWrapper::initializeProduct(const std::string &url, const std::vector<std::string> &productIdentifiers) const
    {
        NSString *NSServerURL = [NSString stringWithCString : url.c_str() encoding : [NSString defaultCStringEncoding]];
        NSURL *serverURL = [NSURL URLWithString : [NSServerURL stringByAddingPercentEscapesUsingEncoding : NSUTF8StringEncoding]];
        NSMutableSet *staticProductIdentifiers = [NSMutableSet set];
        for (std::vector<std::string>::const_iterator it = productIdentifiers.begin(); it != productIdentifiers.end(); ++it)
        {
            [staticProductIdentifiers addObject : [NSString stringWithCString : it->c_str() encoding : [NSString defaultCStringEncoding]]];
        }
        [[InAppPurchaseiOS GetInstance] setProductIdentifiersWithURL : serverURL : staticProductIdentifiers];
    }
    
    bool InAppPurchaseWrapper::canMakePayments(void) const
    {
        return [[InAppPurchaseiOS GetInstance] canMakePayments];
    }
    
    void InAppPurchaseWrapper::requestProducts(void) const
    {
        [[InAppPurchaseiOS GetInstance] requestProducts];
    }
    
    void InAppPurchaseWrapper::buyProduct(const std::string &productIdentifier) const
    {
        NSString *NSProductIdentifier = [NSString stringWithCString : productIdentifier.c_str() encoding : [NSString defaultCStringEncoding]];
        [[InAppPurchaseiOS GetInstance] buyProductWithIdentifier : NSProductIdentifier];
    }
    
    void InAppPurchaseWrapper::buyProduct(const InAppPurchaseItem &product) const
    {
        [[InAppPurchaseiOS GetInstance] buyProductWithItem : product];
    }
    
    bool InAppPurchaseWrapper::isProductPurchased(const std::string &productIdentifier) const
    {
        NSString *NSProductIdentifier = [NSString stringWithCString : productIdentifier.c_str() encoding : [NSString defaultCStringEncoding]];
        return [[InAppPurchaseiOS GetInstance] isProductPurchasedWithIdentifier : NSProductIdentifier];
    }
    
    bool InAppPurchaseWrapper::isProductPurchased(const InAppPurchaseItem &product) const
    {
        return [[InAppPurchaseiOS GetInstance] isProductPurchasedWithItem : product];
    }
    
    void InAppPurchaseWrapper::restoreTransactions(void) const
    {
        [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
    }
    
    std::string InAppPurchaseWrapper::getDownloableContentPath(void) const
    {
        return [[[InAppPurchaseiOS GetInstance] downloableContentPath] UTF8String];
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const std::string &productIdentifier) const
    {
        NSString *NSProductIdentifier = [NSString stringWithCString : productIdentifier.c_str() encoding : [NSString defaultCStringEncoding]];
        return [[[InAppPurchaseiOS GetInstance] downloadContentPathForProductID : NSProductIdentifier] UTF8String];
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const InAppPurchaseItem &product) const
    {
        NSString *NSProductIdentifier = [NSString stringWithCString : product.productIdentifier.c_str() encoding : [NSString defaultCStringEncoding]];
        return [[[InAppPurchaseiOS GetInstance] downloadContentPathForProductID : NSProductIdentifier] UTF8String];
    }
}

# endif
#endif

