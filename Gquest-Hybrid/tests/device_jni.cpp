// Exercise bridge/gquest_device_jni.h against a mock JNIEnv.
//
// What this proves: the call sequence (activity -> package -> manager -> application info
// -> meta-data -> bundle), that GET_META_DATA is actually passed, that every failure path
// returns an empty value instead of a guess, that a pending Java exception is cleared
// rather than left behind, and that every local reference is released again.
//
// What this does not prove: the real Android behaviour. The mock returns what the test
// expects, the signature strings are not validated, and the shim jni.h is not the NDK
// header. A device run remains the only proof of what PackageManager actually returns.
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include "gquest_device_jni.h"

namespace {

enum class Kind { Activity, ContextClass, PackageManager, ManagerClass, ApplicationInfo,
                  InfoClass, Bundle, BundleClass, String, BuildClass };

struct Fake {
    Kind kind;
    std::string text;
};

std::vector<Fake*> g_objects;
// Scenario knobs, set before each run.
bool g_exception = false;
bool g_throw_on_application_info = false;
bool g_throw_on_static_field = false;
bool g_missing_method = false;
bool g_missing_static_field = false;
bool g_meta_data_missing = false;   // metaData field is null
bool g_device_key_missing = false;  // bundle has no such key
std::string g_model, g_device, g_declared;
int g_created = 0, g_deleted = 0;
jint g_last_flags = 0;
std::string g_last_key;

Fake* New(Kind kind, std::string text = {}) {
    auto* fake = new Fake{kind, std::move(text)};
    g_objects.push_back(fake);
    ++g_created;
    return fake;
}

jobject As(Fake* fake) { return reinterpret_cast<jobject>(fake); }
Fake* From(jobject object) { return reinterpret_cast<Fake*>(object); }

void Reset() {
    for (Fake* fake : g_objects) delete fake;
    g_objects.clear();
    g_exception = false;
    g_throw_on_application_info = false;
    g_throw_on_static_field = false;
    g_missing_method = false;
    g_missing_static_field = false;
    g_meta_data_missing = false;
    g_device_key_missing = false;
    g_model.clear();
    g_device.clear();
    g_declared.clear();
    g_created = g_deleted = 0;
    g_last_flags = 0;
    g_last_key.clear();
}

// Fixtures belong to the test, not to the code under test, so the reference accounting
// starts once they exist. They are freed by the next Reset().
struct Fixture {
    Fake* activity;
    Fake* build;
    Fixture() : activity(New(Kind::Activity)), build(New(Kind::BuildClass)) {
        g_created = g_deleted = 0;
    }
};

void CheckBalanced(const char* scenario) {
    if (g_created != g_deleted) {
        std::fprintf(stderr, "FAIL %s: %d local references created, %d released\n",
                     scenario, g_created, g_deleted);
        assert(false);
    }
}

jclass MockGetObjectClass(JNIEnv*, jobject object) {
    switch (From(object)->kind) {
        case Kind::Activity: return As(New(Kind::ContextClass));
        case Kind::PackageManager: return As(New(Kind::ManagerClass));
        case Kind::ApplicationInfo: return As(New(Kind::InfoClass));
        case Kind::Bundle: return As(New(Kind::BundleClass));
        default: g_exception = true; return nullptr;
    }
}

jmethodID MockGetMethodID(JNIEnv*, jclass, const char* name, const char*) {
    if (g_missing_method) return nullptr;
    return const_cast<jmethodID>(reinterpret_cast<const void*>(name));
}

jfieldID MockGetFieldID(JNIEnv*, jclass, const char* name, const char*) {
    return const_cast<jfieldID>(reinterpret_cast<const void*>(name));
}

jfieldID MockGetStaticFieldID(JNIEnv*, jclass, const char* name, const char*) {
    if (g_missing_static_field) return nullptr;
    if (g_throw_on_static_field) { g_exception = true; return nullptr; }
    return const_cast<jfieldID>(reinterpret_cast<const void*>(name));
}

jobject MockGetObjectField(JNIEnv*, jobject, jfieldID field) {
    assert(std::strcmp(static_cast<const char*>(field), "metaData") == 0);
    if (g_meta_data_missing) return nullptr;
    return As(New(Kind::Bundle));
}

jobject MockGetStaticObjectField(JNIEnv*, jclass, jfieldID field) {
    const char* name = static_cast<const char*>(field);
    if (std::strcmp(name, "MODEL") == 0)
        return g_model.empty() ? nullptr : As(New(Kind::String, g_model));
    if (std::strcmp(name, "DEVICE") == 0)
        return g_device.empty() ? nullptr : As(New(Kind::String, g_device));
    return nullptr;
}

jobject MockCallObjectMethodV(JNIEnv*, jobject, jmethodID method, va_list args) {
    const char* name = static_cast<const char*>(method);
    if (std::strcmp(name, "getPackageName") == 0)
        return As(New(Kind::String, "com.gmodvr.qvrx"));
    if (std::strcmp(name, "getPackageManager") == 0)
        return As(New(Kind::PackageManager));
    if (std::strcmp(name, "getApplicationInfo") == 0) {
        auto package = va_arg(args, jstring);
        jint flags = va_arg(args, jint);
        g_last_flags = flags;
        assert(From(reinterpret_cast<jobject>(package))->text == "com.gmodvr.qvrx");
        if (g_throw_on_application_info) { g_exception = true; return nullptr; }
        return As(New(Kind::ApplicationInfo));
    }
    if (std::strcmp(name, "getString") == 0) {
        auto key = va_arg(args, jstring);
        g_last_key = From(reinterpret_cast<jobject>(key))->text;
        if (g_device_key_missing) return nullptr;
        return As(New(Kind::String, g_declared));
    }
    g_exception = true;
    return nullptr;
}

jstring MockNewStringUTF(JNIEnv*, const char* text) { return As(New(Kind::String, text)); }

const char* MockGetStringUTFChars(JNIEnv*, jstring text, jboolean*) {
    return From(reinterpret_cast<jobject>(text))->text.c_str();
}

void MockReleaseStringUTFChars(JNIEnv*, jstring, const char*) {}

void MockDeleteLocalRef(JNIEnv*, jobject object) {
    if (object) ++g_deleted;
}

jboolean MockExceptionCheck(JNIEnv*) { return g_exception ? JNI_TRUE : JNI_FALSE; }
void MockExceptionClear(JNIEnv*) { g_exception = false; }

JNINativeInterface g_table = {
    nullptr, nullptr, nullptr, nullptr,
    MockGetObjectClass, MockGetMethodID, MockGetFieldID, MockGetObjectField,
    MockGetStaticFieldID, MockGetStaticObjectField, MockCallObjectMethodV,
    MockNewStringUTF, MockGetStringUTFChars, MockReleaseStringUTFChars,
    MockDeleteLocalRef, MockExceptionCheck, MockExceptionClear,
};

JNIEnv g_env = {&g_table};

}  // namespace

int main() {
    JNIEnv* env = &g_env;

    // Happy path: both Build fields and the manifest value.
    Reset();
    g_model = "Quest 3S";
    g_device = "panther";
    g_declared = "quest3|quest3s|questpro";
    {
        Fixture f;
        assert(GquestReadJavaStringField(env, As(f.build), "MODEL") == "Quest 3S");
        assert(GquestReadJavaStringField(env, As(f.build), "DEVICE") == "panther");
        assert(GquestReadDeclaredDevices(env, As(f.activity)) == "quest3|quest3s|questpro");
        // GET_META_DATA must be requested, otherwise metaData is null on Android.
        assert(g_last_flags == 128);
        assert(g_last_key == "com.oculus.supportedDevices");
        assert(!env->ExceptionCheck());
    }
    CheckBalanced("happy path");

    // The bundle simply has no such key: empty, not an exception and not a crash.
    Reset();
    g_device_key_missing = true;
    {
        Fixture f;
        assert(GquestReadDeclaredDevices(env, As(f.activity)).empty());
        assert(!env->ExceptionCheck());
    }
    CheckBalanced("missing key");

    // metaData field is null (no GET_META_DATA, or no meta-data at all).
    Reset();
    g_meta_data_missing = true;
    {
        Fixture f;
        assert(GquestReadDeclaredDevices(env, As(f.activity)).empty());
        assert(!env->ExceptionCheck());
    }
    CheckBalanced("no meta-data");

    // A Java exception mid-chain must be cleared, not left pending for the engine.
    Reset();
    g_throw_on_application_info = true;
    {
        Fixture f;
        assert(GquestReadDeclaredDevices(env, As(f.activity)).empty());
        assert(!env->ExceptionCheck());
    }
    CheckBalanced("throwing call");

    // Missing method ids and missing static fields are ordinary failures.
    Reset();
    g_missing_method = true;
    {
        Fixture f;
        assert(GquestReadDeclaredDevices(env, As(f.activity)).empty());
    }
    CheckBalanced("missing method");

    Reset();
    g_missing_static_field = true;
    {
        Fixture f;
        assert(GquestReadJavaStringField(env, As(f.build), "MODEL").empty());
    }
    CheckBalanced("missing field id");

    Reset();
    g_throw_on_static_field = true;
    {
        Fixture f;
        assert(GquestReadJavaStringField(env, As(f.build), "MODEL").empty());
        assert(!env->ExceptionCheck());
    }
    CheckBalanced("throwing static field");

    // An absent Build value is empty, never a substitute string.
    Reset();
    {
        Fixture f;
        assert(GquestReadJavaStringField(env, As(f.build), "MODEL").empty());
    }
    CheckBalanced("absent field value");

    // No activity at all: nothing to read, no call, no reference.
    Reset();
    assert(GquestReadDeclaredDevices(env, nullptr).empty());
    assert(g_created == 0);
    assert(!env->ExceptionCheck());
    CheckBalanced("null activity");

    std::puts("PASS device JNI readers: meta-data requested with GET_META_DATA, absent key "
              "and null bundle stay empty, throwing calls clear the exception, every local "
              "reference released (mock JNIEnv, real Android behaviour still untested)");
    return 0;
}
