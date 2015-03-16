#ifdef __ANDROID__
#include "InAppPurchase.h"
#include "Base.h"

#include <android/sensor.h>
#include <android_native_app_glue.h>
#include <android/log.h>

extern struct android_app* __state;

namespace gameplay
{
	static JNIEnv *getJavaEnv()
	{
		JavaVM *jvm = __state->activity->vm;
		JNIEnv *java_env = NULL;
		jvm->GetEnv((void **)&java_env, JNI_VERSION_1_6);
		jint res = jvm->AttachCurrentThread(&java_env, NULL);
		if (res == JNI_ERR) {
			GP_ERROR("Failed to retrieve JVM environment when entering message pump.");
		}
		GP_ASSERT(java_env);
		return java_env;
	}

    void InAppPurchaseWrapper::initializeProduct(const std::vector<std::string> &/*productIdentifiers*/) const
    {
    }
    
    void InAppPurchaseWrapper::initializeProduct(const std::string &/*url*/) const
    {
    }
    
    void InAppPurchaseWrapper::initializeProduct(const std::string &url, const std::vector<std::string> &productIdentifiers) const
    {
		ANativeActivity *activity = __state->activity;
		JNIEnv *env = getJavaEnv();
		jclass nativeActivityClass = env->GetObjectClass(activity->clazz);
		GP_ASSERT(nativeActivityClass != NULL);

		jmethodID mid_startInAppSetup = env->GetMethodID(nativeActivityClass, "startInAppSetup", "()V");
		GP_ASSERT(mid_startInAppSetup);
		env->CallVoidMethod(activity->clazz, mid_startInAppSetup);
    }
    
    bool InAppPurchaseWrapper::canMakePayments(void) const
    {
		ANativeActivity *activity = __state->activity;
		JNIEnv *env = getJavaEnv();
		jclass nativeActivityClass = env->GetObjectClass(activity->clazz);
		GP_ASSERT(nativeActivityClass != NULL);

		jmethodID mid_canMakePayments = env->GetMethodID(nativeActivityClass, "canMakePayments", "()Z");
		GP_ASSERT(mid_canMakePayments);
		jboolean canMakePayments = env->CallBooleanMethod(activity->clazz, mid_canMakePayments);
        return canMakePayments;
    }
    
    void InAppPurchaseWrapper::requestProducts(void) const
    {
        return;
    }
    
    void InAppPurchaseWrapper::buyProduct(const std::string &/*productIdentifier*/) const
    {
        return;
    }
    
    void InAppPurchaseWrapper::buyProduct(const InAppPurchaseItem &product) const
    {
		ANativeActivity *activity = __state->activity;
		JNIEnv *env = getJavaEnv();
		jclass nativeActivityClass = env->GetObjectClass(activity->clazz);
		GP_ASSERT(nativeActivityClass != NULL);

		jmethodID mid_buyProduct = env->GetMethodID(nativeActivityClass, "buyProduct", "(Ljava/lang/String;)V");
		GP_ASSERT(mid_buyProduct);
		jstring js_productIdentifier = env->NewStringUTF(product.productIdentifier.c_str());
		env->CallVoidMethod(activity->clazz, mid_buyProduct, js_productIdentifier);
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
		ANativeActivity *activity = __state->activity;
		JNIEnv *env = getJavaEnv();
		jclass nativeActivityClass = env->GetObjectClass(activity->clazz);
		GP_ASSERT(nativeActivityClass != NULL);
	
		jmethodID mid_getExtraAreasPurchased = env->GetMethodID(nativeActivityClass, "getExtraAreasPurchased", "()Ljava/util/ArrayList;");
		jobject arrayList = env->CallObjectMethod(activity->clazz, mid_getExtraAreasPurchased);

		jclass arrayClass = env->FindClass("java/util/ArrayList");
		GP_ASSERT(arrayClass);
		jmethodID mid_size = env->GetMethodID(arrayClass, "size", "()I");
		GP_ASSERT(mid_size);
		jmethodID mid_get = env->GetMethodID(arrayClass, "get", "(I)Ljava/lang/Object;");
		GP_ASSERT(mid_get);

		jboolean isCopy;
		jint size = env->CallIntMethod(arrayList, mid_size);
		std::vector<std::string> local_skuList;
		// then we copy the(se) SKU(s) to be processed by checkRestorePurchase
		for (int i = 0; i < size; ++i) {

			const jstring js_sku = static_cast<const jstring>(env->CallObjectMethod(arrayList, mid_get, i));
			const char *nativeSKUName = env->GetStringUTFChars(js_sku, &isCopy);
			local_skuList.push_back(nativeSKUName);
			env->ReleaseStringUTFChars(js_sku, nativeSKUName);
		}

		gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
		for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator cit = the_inAppPurchaseWrapper.getCallbacks().begin(); cit != the_inAppPurchaseWrapper.getCallbacks().end(); ++cit) {
			(*cit)->checkRestorePurchase(local_skuList);
		}

		jmethodID mid_restorePurchasedSKU = env->GetMethodID(nativeActivityClass, "restorePurchasedSKU", "(Ljava/lang/String;)V");
		GP_ASSERT(mid_restorePurchasedSKU);
		
		for (std::vector<std::string>::const_iterator cit = local_skuList.begin(); cit != local_skuList.end(); ++cit) {
			const jstring js_sku = env->NewStringUTF(cit->c_str());
			env->CallVoidMethod(activity->clazz, mid_restorePurchasedSKU, js_sku);
		}
    }
    
    std::string InAppPurchaseWrapper::getDownloableContentPath(void) const
    {
        return "";
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const std::string &productIdentifier) const
    {
		ANativeActivity *activity = __state->activity;
		JNIEnv *env = getJavaEnv();
		jclass nativeActivityClass = env->GetObjectClass(activity->clazz);
		GP_ASSERT(nativeActivityClass);

		jmethodID mid_getExternalFilesDir = env->GetMethodID(nativeActivityClass, "getExternalFilesDir", "(Ljava/lang/String;)Ljava/io/File;");
		GP_ASSERT(mid_getFilesDir);
		jobject fileObject = env->CallObjectMethod(activity->clazz, mid_getExternalFilesDir, NULL);
		GP_ASSERT(fileObject);
		jclass fileClass = env->GetObjectClass(fileObject);
		GP_ASSERT(fileClass);
		jmethodID mid_getAbsolutePath= env->GetMethodID(fileClass, "getAbsolutePath", "()Ljava/lang/String;");
		GP_ASSERT(mid_getAbsolutePath);
		jstring path4Content = static_cast<jstring>(env->CallObjectMethod(fileObject, mid_getAbsolutePath));

		jboolean isCopy;
		const char *nativePath = env->GetStringUTFChars(path4Content, &isCopy);
		const std::string result = nativePath + std::string("/" + productIdentifier + "/");
		env->ReleaseStringUTFChars(path4Content, nativePath);
		
        return result;
    }
    
    std::string InAppPurchaseWrapper::getPathForContent(const InAppPurchaseItem &/*product*/) const
    {
        return "";
    }
}



extern "C" {

JNIEXPORT void JNICALL Java_org_gameplay3d_cockfosters10_MyActivity_failedTransaction(JNIEnv *env, jobject this_object, jstring msg)
{
    jboolean isCopy;
	const char *nativeMsg = env->GetStringUTFChars(msg, &isCopy);
	
	gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
	for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = the_inAppPurchaseWrapper.getCallbacks().begin(); it != the_inAppPurchaseWrapper.getCallbacks().end(); ++it) {
		(*it)->failedTransaction(nativeMsg);
	}
	env->ReleaseStringUTFChars(msg, nativeMsg);
}

JNIEXPORT void JNICALL Java_org_gameplay3d_cockfosters10_MyActivity_productBought(JNIEnv *env, jobject this_object, jstring sku_name)
{
    jboolean isCopy;
	const char *nativeSKUName = env->GetStringUTFChars(sku_name, &isCopy);
	
	gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
	for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = the_inAppPurchaseWrapper.getCallbacks().begin(); it != the_inAppPurchaseWrapper.getCallbacks().end(); ++it) {
		(*it)->productBought(the_inAppPurchaseWrapper.getProducts()[nativeSKUName]);
	}
	env->ReleaseStringUTFChars(sku_name, nativeSKUName);
}



JNIEXPORT void JNICALL Java_org_gameplay3d_cockfosters10_MyActivity_setSKUDetails(JNIEnv *env, jobject this_object, jstring sku_name, jobject sku_details, jboolean mustDownload)
{
	jclass skuDetailsClass = env->GetObjectClass(sku_details);
	GP_ASSERT(skuDetailsClass != NULL);

	jmethodID mid_getTitle = env->GetMethodID(skuDetailsClass, "getTitle", "()Ljava/lang/String;");
	GP_ASSERT(mid_getTitle);
	jmethodID mid_getPrice = env->GetMethodID(skuDetailsClass, "getPrice", "()Ljava/lang/String;");
	GP_ASSERT(mid_getPrice);
	jmethodID mid_getDescription = env->GetMethodID(skuDetailsClass, "getDescription", "()Ljava/lang/String;");
	GP_ASSERT(mid_getDescription);

    jboolean isCopy;
	jstring title = static_cast<jstring>(env->CallObjectMethod(sku_details, mid_getTitle));
	const char *nativeTitle = env->GetStringUTFChars(title, &isCopy);

	jstring price = static_cast<jstring>(env->CallObjectMethod(sku_details, mid_getPrice));
	const char *nativePrice = env->GetStringUTFChars(price, &isCopy);

	jstring description = static_cast<jstring>(env->CallObjectMethod(sku_details, mid_getDescription));
	const char *nativeDescription = env->GetStringUTFChars(description, &isCopy);
	const char *nativeSKUName = env->GetStringUTFChars(sku_name, &isCopy);

	gameplay::InAppPurchaseItem iapi;
	iapi.downloable = mustDownload;
    iapi.localizedTitle = nativeTitle;
	iapi.localizedDescription = nativeDescription;
    iapi.price = nativePrice;
	iapi.imagePreviewPath = "foo";
	iapi.productIdentifier = nativeSKUName;

	gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
    std::map<std::string, gameplay::InAppPurchaseItem> &products = the_inAppPurchaseWrapper.getProducts();
	products[nativeSKUName] = iapi;
	
	env->ReleaseStringUTFChars(sku_name, nativeSKUName);
	env->ReleaseStringUTFChars(description, nativeDescription);
	env->ReleaseStringUTFChars(price, nativePrice);
	env->ReleaseStringUTFChars(title, nativeTitle);
}

JNIEXPORT void JNICALL Java_org_gameplay3d_cockfosters10_MyActivity_SKUDetailsStart(JNIEnv *env, jobject this_object)
{
	gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
    std::map<std::string, gameplay::InAppPurchaseItem> &products = the_inAppPurchaseWrapper.getProducts();
    products.clear();
}

JNIEXPORT void JNICALL Java_org_gameplay3d_cockfosters10_MyActivity_SKUDetailsDone(JNIEnv *env, jobject this_object)
{
	gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
    std::map<std::string, gameplay::InAppPurchaseItem> &products = the_inAppPurchaseWrapper.getProducts();
    for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = the_inAppPurchaseWrapper.getCallbacks().begin(); it != the_inAppPurchaseWrapper.getCallbacks().end(); ++it) {
        (*it)->productsRetrieved(products);
    }
}

JNIEXPORT void JNICALL Java_org_gameplay3d_cockfosters10_MyActivity_contentDownloaded(JNIEnv *env, jobject this_object, jstring contentPath)
{
    jboolean isCopy;
	const char *nativeContentPath = env->GetStringUTFChars(contentPath, &isCopy);

    gameplay::InAppPurchaseContent content;
	content.contentIdentifier = nativeContentPath;

	gameplay::InAppPurchaseWrapper &the_inAppPurchaseWrapper = gameplay::InAppPurchaseWrapper::GetUniqueInstance();
    for (std::vector<gameplay::InAppPurchaseCallback *>::const_iterator it = the_inAppPurchaseWrapper.getCallbacks().begin(); it != the_inAppPurchaseWrapper.getCallbacks().end(); ++it) {
        (*it)->productDownloaded(content);
    }
	env->ReleaseStringUTFChars(contentPath, nativeContentPath);
}
}

#endif