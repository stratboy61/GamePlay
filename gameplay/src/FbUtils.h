#ifndef gameplay_FbUtils_h
#define gameplay_FbUtils_h

#include <vector>
#include <string>

#define FACEBOOK_ID long long

namespace gameplay
{
	enum FacebookFriendContext {
		FFC_CONTEXT_NONE,
		FFC_CONTEXT_REQUEST_SENT,
		FFC_CONTEXT_FRIEND_READ,
		FFC_CONTEXT_FRIEND_RECIEVED,
		FFC_CONTEXT_COUNT
		};

	enum FacebookAsyncReturnEvent {
		FARE_NONE,
		FARE_STATE_CHANGED,
		FARE_ADD_FRIEND,
		FARE_ADD_RECIPIENT,
		FARE_ADD_ACCEPTED_REQUEST,
		FARE_REMOVE_ACCEPTED_REQUEST,
		FARE_ADD_PENDING_REQUEST,
		FARE_REMOVE_PENDING_REQUEST,
		FARE_SCORE_POSTED,
		FARE_USERINFO_RETRIEVED,
		FARE_ERROR,
		FARE_COUNT
		};
    
    class FacebookListener {
    public:
        virtual void onFacebookEvent(FacebookAsyncReturnEvent fare, FACEBOOK_ID id, const std::string &txt = "") = 0;
    };
    
    struct FbFriendInfo
    {
		FbFriendInfo (FACEBOOK_ID id) : m_friendId(id), m_friendName(""), m_score(0), m_requestSent(false), m_ffc(FFC_CONTEXT_NONE), m_self(false) {}
		FbFriendInfo (FACEBOOK_ID id, const std::string &name, int score, bool sent=false, bool self=false) : m_friendId(id), m_friendName(name), m_score(score), m_requestSent(sent), m_ffc(FFC_CONTEXT_NONE), m_self(self) {}
        FACEBOOK_ID m_friendId;
        std::string m_friendName;
        int m_score;
		bool m_requestSent;
		FacebookFriendContext m_ffc;
		bool m_self;
    };
    
    struct FbRequestInfo
    {
        FbRequestInfo(const std::string &id, const std::string &name) : m_requestId(id), m_friendName(name) {}
        FbRequestInfo(const std::string &id, const std::string &name, const std::string &from) : m_requestId(id), m_friendName(name), m_fromId(from) {}
        std::string m_requestId;
        std::string m_friendName;
        std::string m_fromId;
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


