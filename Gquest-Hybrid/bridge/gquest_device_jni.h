// JNI readers for the headset identity: android.os.Build fields and the value of
// com.oculus.supportedDevices in this package's own manifest.
//
// Split out of the bridge so the call sequence, the failure paths and the local
// reference accounting can be exercised on a host against a mock JNIEnv
// (tests/device_jni.cpp). The Android build uses the real NDK jni.h; the test puts
// tests/host_jni first on the include path.
//
// Both readers are read-only and return an empty string on every failure: an unreadable
// field must never turn into a guessed device or an assumed device list.
#pragma once
#include <jni.h>
#include <string>

static std::string GquestReadJavaStringField(JNIEnv* env, jclass cls, const char* name) {
    jfieldID field = env->GetStaticFieldID(cls, name, "Ljava/lang/String;");
    if (env->ExceptionCheck()) { env->ExceptionClear(); return {}; }
    if (!field) return {};
    auto value = static_cast<jstring>(env->GetStaticObjectField(cls, field));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return {}; }
    if (!value) return {};
    std::string text;
    if (const char* chars = env->GetStringUTFChars(value, nullptr)) {
        text = chars;
        env->ReleaseStringUTFChars(value, chars);
    }
    if (env->ExceptionCheck()) env->ExceptionClear();
    env->DeleteLocalRef(value);
    return text;
}

// Activity -> package name -> PackageManager -> ApplicationInfo(metaData) -> Bundle.
// 128 is PackageManager.GET_META_DATA; without it metaData is null.
static std::string GquestReadDeclaredDevices(JNIEnv* env, jobject activity) {
    if (!activity) return {};
    std::string declared;
    jclass contextClass = env->GetObjectClass(activity);
    jclass managerClass = nullptr, infoClass = nullptr, bundleClass = nullptr;
    jstring package = nullptr, key = nullptr;
    jobject manager = nullptr, info = nullptr, bundle = nullptr, value = nullptr;
    do {
        if (!contextClass) break;
        jmethodID getPackageName = env->GetMethodID(
            contextClass, "getPackageName", "()Ljava/lang/String;");
        jmethodID getPackageManager = env->GetMethodID(
            contextClass, "getPackageManager", "()Landroid/content/pm/PackageManager;");
        if (env->ExceptionCheck() || !getPackageName || !getPackageManager) break;
        package = static_cast<jstring>(env->CallObjectMethod(activity, getPackageName));
        manager = env->CallObjectMethod(activity, getPackageManager);
        if (env->ExceptionCheck() || !package || !manager) break;
        managerClass = env->GetObjectClass(manager);
        jmethodID getApplicationInfo = managerClass ? env->GetMethodID(
            managerClass, "getApplicationInfo",
            "(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;") : nullptr;
        if (env->ExceptionCheck() || !getApplicationInfo) break;
        info = env->CallObjectMethod(manager, getApplicationInfo, package, jint(128));
        if (env->ExceptionCheck() || !info) break;
        infoClass = env->GetObjectClass(info);
        jfieldID metadataField = infoClass ? env->GetFieldID(
            infoClass, "metaData", "Landroid/os/Bundle;") : nullptr;
        if (env->ExceptionCheck() || !metadataField) break;
        bundle = env->GetObjectField(info, metadataField);
        if (env->ExceptionCheck() || !bundle) break;
        bundleClass = env->GetObjectClass(bundle);
        jmethodID getString = bundleClass ? env->GetMethodID(
            bundleClass, "getString", "(Ljava/lang/String;)Ljava/lang/String;") : nullptr;
        if (env->ExceptionCheck() || !getString) break;
        key = env->NewStringUTF("com.oculus.supportedDevices");
        if (!key) break;
        value = env->CallObjectMethod(bundle, getString, key);
        if (env->ExceptionCheck() || !value) break;
        if (const char* chars = env->GetStringUTFChars(static_cast<jstring>(value), nullptr)) {
            declared = chars;
            env->ReleaseStringUTFChars(static_cast<jstring>(value), chars);
        }
    } while (false);
    // Any JNI failure above leaves the value empty, which the caller treats as
    // unreadable rather than as an empty device list.
    if (env->ExceptionCheck()) { env->ExceptionClear(); declared.clear(); }
    jobject references[] = {value, key, bundle, info, manager, package};
    for (jobject reference : references)
        if (reference) env->DeleteLocalRef(reference);
    jclass classes[] = {bundleClass, infoClass, managerClass, contextClass};
    for (jclass reference : classes)
        if (reference) env->DeleteLocalRef(reference);
    return declared;
}
