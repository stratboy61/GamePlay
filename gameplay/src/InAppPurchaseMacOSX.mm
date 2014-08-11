#if __APPLE__
# include "TargetConditionals.h"
# if TARGET_OS_MAC

#include "InAppPurchase.h"

namespace gameplay
{
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
        return;
    }
    
    bool InAppPurchaseWrapper::canMakePayments(void) const
    {
        return false;
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
    
    void InAppPurchaseWrapper::restoreTransactions(void) const
    {
        return;
    }
    
    std::string InAppPurchaseWrapper::getDownloableContentPath(void) const
    {
        return "";
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const std::string &/*productIdentifier*/) const
    {
        return "";
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const InAppPurchaseItem &/*product*/) const
    {
        return "";
    }
}

# endif
#endif
