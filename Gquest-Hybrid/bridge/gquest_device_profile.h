// Headset identification from android.os.Build.MODEL / .DEVICE.
//
// Kept as a pure string classifier with no JNI so it can be tested on a host:
// the bridge only has to read the two Java strings and hand them over.
//
// Meta reports Build.MODEL as "Quest 3", "Quest 3S", "Quest 2", "Quest Pro" and
// Build.DEVICE as the platform codename (eureka, panther, hollywood, seacliff).
// Both are checked because either can be unavailable on a given build.
#pragma once
#include <cctype>
#include <cstring>

enum class GquestDevice { Unknown, Quest2, Quest3, Quest3S, QuestPro };

// Compare ignoring surrounding ASCII whitespace and letter case. A model string
// with a stray trailing space must still match.
static bool GquestModelEquals(const char* value, const char* expected) {
    if (!value || !expected) return false;
    while (*value == ' ' || *value == '\t') ++value;
    while (*expected == ' ' || *expected == '\t') ++expected;
    const char* valueEnd = value + std::strlen(value);
    while (valueEnd > value && (valueEnd[-1] == ' ' || valueEnd[-1] == '\t' ||
                                valueEnd[-1] == '\r' || valueEnd[-1] == '\n')) --valueEnd;
    const char* expectedEnd = expected + std::strlen(expected);
    while (expectedEnd > expected && (expectedEnd[-1] == ' ' || expectedEnd[-1] == '\t')) --expectedEnd;
    if ((valueEnd - value) != (expectedEnd - expected)) return false;
    for (; value < valueEnd; ++value, ++expected) {
        if (std::tolower(static_cast<unsigned char>(*value)) !=
            std::tolower(static_cast<unsigned char>(*expected))) return false;
    }
    return true;
}

// Order matters: "Quest 3S" begins with "Quest 3", so the more specific model has
// to be tested first or every 3S is misread as a Quest 3.
static GquestDevice GquestDeviceFromModel(const char* model) {
    if (GquestModelEquals(model, "Quest 3S")) return GquestDevice::Quest3S;
    if (GquestModelEquals(model, "Quest 3")) return GquestDevice::Quest3;
    if (GquestModelEquals(model, "Quest 2")) return GquestDevice::Quest2;
    if (GquestModelEquals(model, "Quest Pro")) return GquestDevice::QuestPro;
    return GquestDevice::Unknown;
}

static GquestDevice GquestDeviceFromCodename(const char* device) {
    if (GquestModelEquals(device, "panther")) return GquestDevice::Quest3S;
    if (GquestModelEquals(device, "eureka")) return GquestDevice::Quest3;
    if (GquestModelEquals(device, "hollywood")) return GquestDevice::Quest2;
    if (GquestModelEquals(device, "seacliff")) return GquestDevice::QuestPro;
    return GquestDevice::Unknown;
}

// The model string is what the user sees, so it wins; the codename is only a
// fallback for builds where Build.MODEL is empty or renamed.
static GquestDevice GquestClassifyDevice(const char* model, const char* device) {
    const GquestDevice fromModel = GquestDeviceFromModel(model);
    if (fromModel != GquestDevice::Unknown) return fromModel;
    return GquestDeviceFromCodename(device);
}

// Must match the ids in work/gquest-ui/lua/autorun/client/gquest_vr_profiles.lua
// and the device names in Gquest-Hybrid/src/lib.rs. Unknown returns null so the
// caller exports nothing and the saved profile is left untouched.
static const char* GquestDeviceId(GquestDevice device) {
    switch (device) {
        case GquestDevice::Quest3: return "quest3";
        case GquestDevice::Quest3S: return "quest3s";
        case GquestDevice::Quest2: return "quest2";
        case GquestDevice::QuestPro: return "questpro";
        default: return nullptr;
    }
}
