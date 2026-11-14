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
#include <cstddef>
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
//
// The Oculus_* spellings are what Meta documents as a possible reported value
// ("reported as Oculus_Quest_2"), so both spellings are accepted. Anything else stays
// unknown on purpose: guessing a headset is worse than keeping the saved profile.
static GquestDevice GquestDeviceFromModel(const char* model) {
    if (GquestModelEquals(model, "Quest 3S") || GquestModelEquals(model, "Oculus_Quest_3S"))
        return GquestDevice::Quest3S;
    if (GquestModelEquals(model, "Quest 3") || GquestModelEquals(model, "Oculus_Quest_3"))
        return GquestDevice::Quest3;
    if (GquestModelEquals(model, "Quest 2") || GquestModelEquals(model, "Oculus_Quest_2"))
        return GquestDevice::Quest2;
    if (GquestModelEquals(model, "Quest Pro") || GquestModelEquals(model, "Oculus_Quest_Pro"))
        return GquestDevice::QuestPro;
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

// What the reported model and the manifest disagree about. Pure diagnosis: nothing here
// changes which profile is used, it only decides whether the discrepancy is worth a
// warning line.
enum class GquestDeviceWarning { None, NotDeclared, AmbiguousCompat };

// Is this device one of the entries in a com.oculus.supportedDevices value?
//
// Compared as whole tokens: "quest3" must not match inside "quest3s", or every 3S-only
// package would look like it supports the Quest 3.
static bool GquestDeviceDeclared(GquestDevice device, const char* supportedDevices) {
    const char* id = GquestDeviceId(device);
    if (!id || !supportedDevices) return false;
    const std::size_t idLength = std::strlen(id);
    const char* cursor = supportedDevices;
    while (*cursor) {
        while (*cursor == '|' || *cursor == ' ' || *cursor == '\t') ++cursor;
        const char* start = cursor;
        while (*cursor && *cursor != '|') ++cursor;
        const char* end = cursor;
        while (end > start && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' ||
                               end[-1] == '\n')) --end;
        if (static_cast<std::size_t>(end - start) == idLength) {
            bool same = true;
            for (std::size_t i = 0; i < idLength && same; ++i)
                same = std::tolower(static_cast<unsigned char>(start[i])) == id[i];
            if (same) return true;
        }
    }
    return false;
}

// Compatibility mode is chosen from the manifest, not from the hardware. So:
// - a model the manifest does not declare means the reported headset and the declared
//   support disagree, and the app may be running in compatibility mode;
// - a manifest that lists quest3 but not quest3s cannot tell a Quest 3S in compatibility
//   mode apart from a real Quest 3, which is exactly the case that misreads a 3S.
// An unknown device or unreadable manifest is not a contradiction: nothing to compare.
static GquestDeviceWarning GquestDeviceConsistency(GquestDevice device,
                                                   const char* supportedDevices) {
    if (device == GquestDevice::Unknown) return GquestDeviceWarning::None;
    if (!supportedDevices || !*supportedDevices) return GquestDeviceWarning::None;
    if (!GquestDeviceDeclared(device, supportedDevices)) return GquestDeviceWarning::NotDeclared;
    if (device == GquestDevice::Quest3 &&
        !GquestDeviceDeclared(GquestDevice::Quest3S, supportedDevices))
        return GquestDeviceWarning::AmbiguousCompat;
    return GquestDeviceWarning::None;
}
