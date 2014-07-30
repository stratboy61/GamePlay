#include "FbUtils.h"
#include "gameplay.h"

using namespace gameplay;

const std::string& FbBundle::getObject(const std::string& key) const
{
    for(unsigned int i=0; i<m_data.size(); i+=2)
    {
        if(m_data[i+1] == key)
        {
            return m_data[i];
        }
    }
    
    GP_ASSERT(false); // not found;
    static std::string empty;
    return empty;
}

void FbBundle::show() const
{
    for(unsigned int i=0; i<m_data.size(); i+=2)
    {
        GP_WARN((m_data[i] + " : " + m_data[i+1]).c_str());
    }
    
}

void FbBundle::addPair(const std::string& object, const std::string& key)
{
    m_data.push_back(object);
    m_data.push_back(key);
}

