#include <cassert>
#include <cstdio>
#include <cstring>
#include "gquest_device_profile.h"

int main() {
    // "Quest 3S" starts with "Quest 3": the specific model must win.
    assert(GquestClassifyDevice("Quest 3S", "") == GquestDevice::Quest3S);
    assert(GquestClassifyDevice("Quest 3", "") == GquestDevice::Quest3);
    assert(GquestClassifyDevice("Quest 3S", "eureka") == GquestDevice::Quest3S);

    // Platform codenames work when the model string is missing.
    assert(GquestClassifyDevice("", "panther") == GquestDevice::Quest3S);
    assert(GquestClassifyDevice("", "eureka") == GquestDevice::Quest3);
    assert(GquestClassifyDevice("", "hollywood") == GquestDevice::Quest2);
    assert(GquestClassifyDevice("", "seacliff") == GquestDevice::QuestPro);

    // Case, surrounding whitespace and a trailing newline must not matter.
    assert(GquestClassifyDevice("quest 3s", "  ") == GquestDevice::Quest3S);
    assert(GquestClassifyDevice(" Quest 3 \n", nullptr) == GquestDevice::Quest3);
    assert(GquestClassifyDevice("\tQUEST PRO\t", "") == GquestDevice::QuestPro);

    // Meta documents the Oculus_* spelling as a possible reported value.
    assert(GquestClassifyDevice("Oculus_Quest_3S", "") == GquestDevice::Quest3S);
    assert(GquestClassifyDevice("Oculus_Quest_3", "") == GquestDevice::Quest3);
    assert(GquestClassifyDevice("Oculus_Quest_2", "") == GquestDevice::Quest2);
    assert(GquestClassifyDevice("Oculus_Quest_Pro", "") == GquestDevice::QuestPro);
    assert(GquestClassifyDevice("Oculus_Quest_30", "") == GquestDevice::Unknown);

    // A known model is not overridden by an unrelated codename.
    assert(GquestClassifyDevice("Quest 2", "eureka") == GquestDevice::Quest2);

    // Unknown hardware stays unknown: the caller then keeps the saved profile.
    assert(GquestClassifyDevice(nullptr, nullptr) == GquestDevice::Unknown);
    assert(GquestClassifyDevice("", "") == GquestDevice::Unknown);
    assert(GquestClassifyDevice("Some Other Headset", "foo") == GquestDevice::Unknown);
    // Near misses must not be accepted.
    assert(GquestClassifyDevice("Quest 30", "") == GquestDevice::Unknown);
    assert(GquestClassifyDevice("Quest", "") == GquestDevice::Unknown);

    // Exported ids are the ones the Lua profile module and the Rust policy use.
    assert(std::strcmp(GquestDeviceId(GquestDevice::Quest3), "quest3") == 0);
    assert(std::strcmp(GquestDeviceId(GquestDevice::Quest3S), "quest3s") == 0);
    assert(std::strcmp(GquestDeviceId(GquestDevice::Quest2), "quest2") == 0);
    assert(std::strcmp(GquestDeviceId(GquestDevice::QuestPro), "questpro") == 0);
    assert(GquestDeviceId(GquestDevice::Unknown) == nullptr);

    std::puts("PASS device model classification: 3S beats 3, case/whitespace/near-miss guards, "
              "codename fallback, nulls and stable ids");
}
