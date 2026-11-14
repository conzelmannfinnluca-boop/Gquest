// Host-only stand-in for the Android <jni.h>. NOT the NDK header.
//
// The bridge includes the real NDK jni.h; this file is only reached because the host
// test puts tests/host_jni first on the include path. It declares exactly the JNI surface
// the device readers use, so bridge/gquest_device_jni.h compiles unchanged on a host and
// can be driven by a mock environment (tests/device_jni.cpp).
//
// Consequence to keep in mind: this proves the call sequence, the guards and the local
// reference accounting, not the real ABI. Signature strings and struct layouts are not
// validated by it, and a real device run is still the only proof that Android returns
// what the mock returns.
#pragma once
#include <cstdarg>
#include <cstdint>

typedef int8_t jboolean;
typedef int8_t jbyte;
typedef uint16_t jchar;
typedef int16_t jshort;
typedef int32_t jint;
typedef int64_t jlong;
typedef float jfloat;
typedef double jdouble;
typedef jint jsize;

#define JNI_TRUE 1
#define JNI_FALSE 0

struct _jobject;
typedef _jobject* jobject;
typedef _jobject* jclass;
typedef _jobject* jstring;
typedef _jobject* jthrowable;

typedef void* jmethodID;
typedef void* jfieldID;

struct JNIEnv;

struct JNINativeInterface {
    void* reserved0;
    void* reserved1;
    void* reserved2;
    void* reserved3;
    jclass (*GetObjectClass)(JNIEnv*, jobject);
    jmethodID (*GetMethodID)(JNIEnv*, jclass, const char*, const char*);
    jfieldID (*GetFieldID)(JNIEnv*, jclass, const char*, const char*);
    jobject (*GetObjectField)(JNIEnv*, jobject, jfieldID);
    jfieldID (*GetStaticFieldID)(JNIEnv*, jclass, const char*, const char*);
    jobject (*GetStaticObjectField)(JNIEnv*, jclass, jfieldID);
    jobject (*CallObjectMethodV)(JNIEnv*, jobject, jmethodID, va_list);
    jstring (*NewStringUTF)(JNIEnv*, const char*);
    const char* (*GetStringUTFChars)(JNIEnv*, jstring, jboolean*);
    void (*ReleaseStringUTFChars)(JNIEnv*, jstring, const char*);
    void (*DeleteLocalRef)(JNIEnv*, jobject);
    jboolean (*ExceptionCheck)(JNIEnv*);
    void (*ExceptionClear)(JNIEnv*);
};

struct JNIEnv {
    const JNINativeInterface* functions;

    jclass GetObjectClass(jobject object) { return functions->GetObjectClass(this, object); }
    jmethodID GetMethodID(jclass cls, const char* name, const char* signature) {
        return functions->GetMethodID(this, cls, name, signature);
    }
    jfieldID GetFieldID(jclass cls, const char* name, const char* signature) {
        return functions->GetFieldID(this, cls, name, signature);
    }
    jobject GetObjectField(jobject object, jfieldID field) {
        return functions->GetObjectField(this, object, field);
    }
    jfieldID GetStaticFieldID(jclass cls, const char* name, const char* signature) {
        return functions->GetStaticFieldID(this, cls, name, signature);
    }
    jobject GetStaticObjectField(jclass cls, jfieldID field) {
        return functions->GetStaticObjectField(this, cls, field);
    }
    jobject CallObjectMethod(jobject object, jmethodID method, ...) {
        va_list args;
        va_start(args, method);
        jobject result = functions->CallObjectMethodV(this, object, method, args);
        va_end(args);
        return result;
    }
    jstring NewStringUTF(const char* text) { return functions->NewStringUTF(this, text); }
    const char* GetStringUTFChars(jstring text, jboolean* copy) {
        return functions->GetStringUTFChars(this, text, copy);
    }
    void ReleaseStringUTFChars(jstring text, const char* chars) {
        functions->ReleaseStringUTFChars(this, text, chars);
    }
    void DeleteLocalRef(jobject object) { functions->DeleteLocalRef(this, object); }
    jboolean ExceptionCheck() { return functions->ExceptionCheck(this); }
    void ExceptionClear() { functions->ExceptionClear(this); }
};
