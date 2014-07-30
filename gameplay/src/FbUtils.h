
#ifndef gameplay_FbUtils_h
#define gameplay_FbUtils_h

#include <vector>
#include <string>

namespace gameplay
{
    
    class FacebookListener
    {
    public: 
        virtual void onFacebookEvent(const std::string& eventName, const std::string& message="") = 0;
    };
    
    /* Facebook Events Names */
    static const std::string SESSION_STATE_CHANGED  = "SESSION_STATE_CHANGED";
    static const std::string INCOMING_NOTIFICATION  = "INCOMING_NOTIFICATION";
    static const std::string FACEBOOK_ERROR         = "FACEBOOK_ERROR";
    
    
    struct FbFriendInfo
    {
        std::string m_name;
        std::string m_id;
        int         m_score;
    };
      
    class FbBundle
    {
    public:
        FbBundle() {}
        ~FbBundle() {}
        
        const std::string& getObject(const std::string& key) const;
        
        void show() const;
        
        void addPair(const std::string& object, const std::string& key);
        
        const std::vector<std::string>& getData() const
        {
            return m_data;
        }
        
    private:
        std::vector<std::string> m_data;
    };
    
}

#endif


