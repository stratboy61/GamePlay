#include <algorithm>

#include "InAppPurchase.h"

namespace gameplay
{    
    InAppPurchaseCallback::InAppPurchaseCallback(void)
    {
        InAppPurchaseWrapper::GetUniqueInstance().addCallback(this);
    }
    
    InAppPurchaseCallback::InAppPurchaseCallback(const InAppPurchaseCallback &)
    {
        InAppPurchaseWrapper::GetUniqueInstance().addCallback(this);
    }
    
    InAppPurchaseCallback &InAppPurchaseCallback::operator=(const InAppPurchaseCallback &)
    {
        return *this;
    }
    
    InAppPurchaseCallback::~InAppPurchaseCallback(void)
    {
        InAppPurchaseWrapper::GetUniqueInstance().removeCallback(this);
    }
    
    InAppPurchaseWrapper *InAppPurchaseWrapper::Instance = NULL;
    
    InAppPurchaseWrapper::InAppPurchaseWrapper(void)
    : callbacks()
    {
        return;
    }
    
    InAppPurchaseWrapper::~InAppPurchaseWrapper(void)
    {
        return;
    }
    
    void InAppPurchaseWrapper::addCallback(gameplay::InAppPurchaseCallback *callback)
    {
        callbacks.push_back(callback);
    }
    
    void InAppPurchaseWrapper::removeCallback(gameplay::InAppPurchaseCallback *callback)
    {
        std::vector<gameplay::InAppPurchaseCallback *>::iterator found = std::find(callbacks.begin(), callbacks.end(), callback);
        if (found != callbacks.end())
        {
            callbacks.erase(found);
        }
    }
    
    const std::vector<gameplay::InAppPurchaseCallback *> &InAppPurchaseWrapper::getCallbacks(void) const
    {
        return callbacks;
    }
    
    std::map<std::string, InAppPurchaseItem> &InAppPurchaseWrapper::getProducts(void)
    {
        return products;
    }
    
    InAppPurchaseWrapper &InAppPurchaseWrapper::GetUniqueInstance(void)
    {
        if (!InAppPurchaseWrapper::Instance)
        {
            InAppPurchaseWrapper::Instance = new InAppPurchaseWrapper;
        }
        return *InAppPurchaseWrapper::Instance;
    }
    
    void InAppPurchaseWrapper::DestroyUniqueInstance(void)
    {
        delete InAppPurchaseWrapper::Instance;
        InAppPurchaseWrapper::Instance = NULL;
    }
}

