// Pose decoding from the XR snapshot: which values are usable, and what "usable" means.
//
// Extracted from gquest_vr_lua.h so these rules can be tested directly instead of only
// through the Lua bindings. Only the platform-independent part moved: the offsets into the
// snapshot stay with the caller, because they are a property of the XR interface and not of
// the arithmetic.
//
// Lives in bridge/ rather than a separate core/ tree on purpose: the shared-core layout is
// still an open decision (E1 in PROJECT_STATUS.md), and this header is used unchanged in
// every one of those layouts.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstring>

namespace GquestPose {

struct Vec3 {
    float x, y, z;
};

// QAngle order: pitch (x), yaw (y), roll (z), in degrees.
struct Angles {
    float pitch, yaw, roll;
};

struct Snapshot {
    Vec3 position;
    Angles angle;
};

// The snapshot carries metres, the playspace convention uses inches. Y and Z are swapped
// and Z is negated, which is what the Lua tracking provider and the native finger sampling
// already expect; changing it here would move every pose at once.
constexpr float kUnitsPerMetre = 39.370098f;
constexpr float kDegreesPerRadian = 57.2957795131f;

// Squared-norm window for a usable orientation. Outside it the quaternion is not a
// rotation, and the angles derived from it would still look plausible - which is worse than
// reporting the pose as invalid.
constexpr float kMinNormSquared = 0.5f;
constexpr float kMaxNormSquared = 1.5f;

static bool Finite(const float* values, std::size_t count) {
    for (std::size_t index = 0; index < count; ++index)
        if (!std::isfinite(values[index])) return false;
    return true;
}

static Angles AnglesFromQuaternion(const float* q) {
    const float x = q[0], y = q[1], z = q[2], w = q[3];
    return {
        std::asin(std::max(-1.0f, std::min(1.0f, 2 * (w * y - z * x)))) * kDegreesPerRadian,
        std::atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)) * kDegreesPerRadian,
        std::atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y)) * kDegreesPerRadian,
    };
}

// Returns false for a non-finite component or an unusable orientation, and leaves `out`
// untouched in that case: the caller publishes zeroed values instead of a guess.
// [[maybe_unused]]: this header is shared, and a consumer that only needs Snapshot/Vec3
// (the playspace math) must not warn about the decoder it does not call.
[[maybe_unused]] static bool Decode(const unsigned char* snapshot, std::size_t positionOffset,
                   std::size_t quaternionOffset, Snapshot& out) {
    float position[3];
    float orientation[4];
    std::memcpy(position, snapshot + positionOffset, sizeof(position));
    std::memcpy(orientation, snapshot + quaternionOffset, sizeof(orientation));
    if (!Finite(position, 3) || !Finite(orientation, 4)) return false;
    float norm = 0;
    for (float value : orientation) norm += value * value;
    if (norm < kMinNormSquared || norm > kMaxNormSquared) return false;
    out.position = {position[0] * kUnitsPerMetre, -position[2] * kUnitsPerMetre,
                    position[1] * kUnitsPerMetre};
    out.angle = AnglesFromQuaternion(orientation);
    return true;
}

}  // namespace GquestPose
