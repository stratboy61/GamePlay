#ifdef WIN32
#include "Base.h"
#include "Platform.h"
#include "InAppPurchase.h"
#include <GL/wglew.h>

namespace gameplay
{
	DWORD WINAPI initializeProductThread(void* pContext)
	{
		Platform::sleep(667);

		char msg[256];
		InAppPurchaseWrapper &the_inAppPurchaseWrapper = InAppPurchaseWrapper::GetUniqueInstance();
		std::map<std::string, InAppPurchaseItem> &products = the_inAppPurchaseWrapper.getProducts();
		for (int i = 0; i < 4; ++i) {

			InAppPurchaseItem iapi;
			iapi.downloable = true;
			sprintf(msg, "localizedTitle#%d", i);
			iapi.localizedTitle = msg;
			sprintf(msg, "localizedDescription#%d", i);
			iapi.localizedDescription = msg;
			iapi.price = 665.99;
			iapi.imagePreviewPath = "foo";
			sprintf(msg, "productIdentifier#%d", i);
			iapi.productIdentifier = msg;

			products[iapi.productIdentifier] = iapi;
		}
		for (std::vector<InAppPurchaseCallback *>::const_iterator it = the_inAppPurchaseWrapper.getCallbacks().begin(); it != the_inAppPurchaseWrapper.getCallbacks().end(); ++it) {
			(*it)->productsRetrieved(products);
		}
		return 0;
	}

    void InAppPurchaseWrapper::initializeProduct(const std::vector<std::string> &/*productIdentifiers*/) const
    {
        return;
    }
    
    void InAppPurchaseWrapper::initializeProduct(const std::string &/*url*/) const
    {
        return;
    }
    
    void InAppPurchaseWrapper::initializeProduct(const std::string &/*url*/, const std::vector<std::string> &/*productIdentifiers*/) const
    {
		HANDLE h = CreateThread( NULL, 0, initializeProductThread, NULL, 0L, NULL );
		WaitForSingleObject(h, 2000);
    }
    
    bool InAppPurchaseWrapper::canMakePayments(void) const
    {
        return true;
    }
    
    void InAppPurchaseWrapper::requestProducts(void) const
    {
        return;
    }
    
    void InAppPurchaseWrapper::buyProduct(const std::string &/*productIdentifier*/) const
    {
        return;
    }
    
    void InAppPurchaseWrapper::buyProduct(const InAppPurchaseItem &/*product*/) const
    {
        return;
    }
    
    bool InAppPurchaseWrapper::isProductPurchased(const std::string &/*productIdentifier*/) const
    {
        return false;
    }
    
    bool InAppPurchaseWrapper::isProductPurchased(const InAppPurchaseItem &/*product*/) const
    {
        return false;
    }

	DWORD WINAPI restoreTransactionsThread(void* pContext)
	{
		InAppPurchaseContent iapc;
		InAppPurchaseWrapper &the_inAppPurchaseWrapper = InAppPurchaseWrapper::GetUniqueInstance();
		for (int i = 0; i < 15722; ++i) {

			Platform::sleep(9);
			for (std::vector<InAppPurchaseCallback *>::const_iterator it = the_inAppPurchaseWrapper.getCallbacks().begin(); it != the_inAppPurchaseWrapper.getCallbacks().end(); ++it) {
				iapc.progress = i;
				(*it)->productDownloading(iapc);
			}
		}
		return 0;
	}

    void InAppPurchaseWrapper::restoreTransactions(void) const
    {
		HANDLE h = CreateThread( NULL, 0, restoreTransactionsThread, NULL, 0L, NULL );
		WaitForSingleObject(h, 2000);
    }
    
    std::string InAppPurchaseWrapper::getDownloableContentPath(void) const
    {
        return "";
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const std::string &productIdentifier) const
    {
		std::string result("res/extras/");
		return result + productIdentifier + "/";
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const InAppPurchaseItem &/*product*/) const
    {
        return "";
    }
}
#endif