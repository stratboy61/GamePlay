#ifndef gameplay_FbUtils_h
#define gameplay_FbUtils_h

#include <vector>
#include <string>

#define FACEBOOK_ID long long

namespace gameplay
{
	enum FacebookAsyncReturnEvent {
		FARE_NONE,
		FARE_STATE_CHANGED,
		FARE_ADD_FRIEND,
		FARE_ADD_RECIPIENT,
		FARE_ADD_REQUEST,
		FARE_REMOVE_REQUEST,
		FARE_ERROR,
		FARE_COUNT
		};
    
    class FacebookListener {
    public:
        virtual void onFacebookEvent(FacebookAsyncReturnEvent fare, FACEBOOK_ID id, const std::string &txt = "") = 0;
    };
    
    struct FbFriendInfo
    {
		FbFriendInfo (FACEBOOK_ID id) : m_friendId(id), m_friendName(""), m_score(0), m_requestSent(false), m_self(false) {}
		FbFriendInfo (FACEBOOK_ID id, const std::string &name, int score, bool sent=false, bool self=false) : m_friendId(id), m_friendName(name), m_score(score), m_requestSent(sent), m_self(self) {}
        FACEBOOK_ID m_friendId;
        std::string m_friendName;
        int m_score;
		bool m_requestSent;
		bool m_self;
    };
    
    struct FbRequestInfo
    {
        FbRequestInfo(const std::string &id, const std::string &name) : m_requestId(id), m_friendName(name) {}
        std::string m_requestId;
        std::string m_friendName;
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


