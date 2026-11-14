// Print the GQuest device id for a given Build.MODEL / Build.DEVICE pair.
//
// Used by tools/capture_device.py so the recorded value comes from the same
// classifier the bridge uses, not from a second implementation that could drift.
//
// Usage: device_id <model> <device>
// Exit:  0 = recognised (id on stdout), 1 = unknown, 2 = bad usage.
#include <cstdio>

#include "gquest_device_profile.h"

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: device_id <model> <device>\n");
        return 2;
    }
    const char* id = GquestDeviceId(GquestClassifyDevice(argv[1], argv[2]));
    if (!id) {
        std::printf("unknown\n");
        return 1;
    }
    std::printf("%s\n", id);
    return 0;
}
