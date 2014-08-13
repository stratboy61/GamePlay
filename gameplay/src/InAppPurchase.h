#pragma once

#include <string>
#include <vector>
#include <map>

namespace gameplay
{
    struct InAppPurchaseItem
    {
        bool downloable;
        std::string localizedDescription;
        std::string localizedTitle;
        std::string price;
        std::string imagePreviewPath;
        std::string productIdentifier;
    };
    
    struct InAppPurchaseContent
    {
        std::string contentIdentifier;
        long long contentLength;
        std::string contentDirectory;
        std::vector<std::string> contentFilesPath;
        std::string contentVersion;
        float progress;
        std::string timeRemaining;
    };

    class InAppPurchaseCallback
    {
        friend class InAppPurchaseWrapper;
        
    public:
        InAppPurchaseCallback(void);
        InAppPurchaseCallback(const InAppPurchaseCallback &);
        InAppPurchaseCallback &operator=(const InAppPurchaseCallback &);
        ~InAppPurchaseCallback(void);
        
        virtual void productsIdentifiersRetrieved(const std::vector<std::string> &productsIdentifiers) = 0;
        virtual void productsRetrieved(const std::map<std::string, InAppPurchaseItem> &products) = 0;
        virtual void productBought(const InAppPurchaseItem &product) = 0;
        virtual void productDownloading(const InAppPurchaseContent &product) = 0;
        virtual void productDownloaded(const InAppPurchaseContent &product) = 0;
        virtual void imagePreviewLoaded(const InAppPurchaseItem &item) = 0;
    };
    
    class InAppPurchaseWrapper
    {
        friend class InAppPurchaseCallback;
        
    private:
        static InAppPurchaseWrapper *Instance;
        
        std::vector<gameplay::InAppPurchaseCallback *> callbacks;
        std::map<std::string, InAppPurchaseItem> products;
        
        InAppPurchaseWrapper(void);
        InAppPurchaseWrapper(const InAppPurchaseWrapper &);
        InAppPurchaseWrapper &operator=(const InAppPurchaseWrapper &);
        ~InAppPurchaseWrapper(void);

        void addCallback(gameplay::InAppPurchaseCallback *callback);
        void removeCallback(gameplay::InAppPurchaseCallback *callback);
        
    public:
        static InAppPurchaseWrapper &GetUniqueInstance(void);
        static void DestroyUniqueInstance(void);
        
        void initializeProduct(const std::vector<std::string> &productIdentifiers) const;
        void initializeProduct(const std::string &url) const;
        void initializeProduct(const std::string &url, const std::vector<std::string> &productIdentifiers) const;
        bool canMakePayments(void) const;
        void requestProducts(void) const;
        void buyProduct(const std::string &productIdentifier) const;
        void buyProduct(const InAppPurchaseItem &product) const;
        bool isProductPurchased(const std::string &productIdentifier) const;
        bool isProductPurchased(const InAppPurchaseItem &product) const;
        void restoreTransactions(void) const;
        std::string getDownloableContentPath(void) const;
        std::string getPathForContent(const std::string &productIdentifier) const;
        std::string getPathForContent(const InAppPurchaseItem &product) const;
        const std::vector<gameplay::InAppPurchaseCallback *> &getCallbacks(void) const;
        std::map<std::string, InAppPurchaseItem> &getProducts(void);
    };
}