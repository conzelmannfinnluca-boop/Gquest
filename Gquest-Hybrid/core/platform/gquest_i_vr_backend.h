// The runtime side of VR: one frame of poses in, haptics out.
//
// This is the seam that makes a second host possible at all: the GDroid host copies poses
// from the XR input, a test host generates them, and the core cannot tell the difference.
#pragma once
#include <cmath>
#include "gquest_platform_types.h"

namespace GquestPlatform {

inline bool GquestHapticArgumentsAllowed(float seconds, float frequencyHz, float amplitude) {
    if (!std::isfinite(seconds) || !std::isfinite(frequencyHz) || !std::isfinite(amplitude))
        return false;
    return seconds > 0.0f && seconds <= kMaxHapticSeconds &&
           frequencyHz >= kMinHapticHz && frequencyHz <= kMaxHapticHz &&
           amplitude >= 0.0f && amplitude <= kMaxHapticAmplitude;
}

struct IVRBackend {
    virtual ~IVRBackend() = default;
    // False when nothing usable could be read at all. A single hand may be invalid while the
    // frame itself is fine; the caller checks handValid.
    virtual bool Poll(VrFrame& out) = 0;
    // Out-of-range values are not forwarded to the runtime. Returns whether anything was
    // sent, so a caller can tell "no haptic" from "haptic without effect".
    virtual bool Haptic(Hand hand, float seconds, float frequencyHz, float amplitude) = 0;
};

}  // namespace GquestPlatform
