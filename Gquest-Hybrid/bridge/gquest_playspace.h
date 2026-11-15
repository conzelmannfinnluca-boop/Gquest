// Playspace math: turning the world, recentring it on the player, seated/standing height.
//
// Pure arithmetic with no platform, no XR call and no engine state, so it runs unchanged on
// a host and on the device. Nothing consumes it yet - the consumer arrives with the
// platform split that decision E1 in PROJECT_STATUS.md settles - but the conventions below
// are what every candidate layout needs, and they are cheaper to fix now than after three
// implementations exist.
//
// Conventions, chosen once and tested:
// - Y is up, the horizontal plane is X/Z, angles are degrees.
// - "Yaw" rotates the world around the player; a positive yaw turns the world clockwise
//   when seen from above, which turns the player counter-clockwise.
// - Yaw always stays in (-180, 180], so a long session cannot drift into huge numbers where
//   float precision decays.
// - Recentring cancels horizontal position and heading only. Height is never flattened by a
//   recentre; the stance offset is the one thing that moves it.
// - The recentre anchor lives in *tracking* space. Stored in world space it would be a
//   snapshot of one yaw, and the very next turn would rotate the pivot with it.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include "gquest_pose_snapshot.h"

namespace GquestPlayspace {

using GquestPose::Snapshot;
using GquestPose::Vec3;

// Comfort defaults, not measurements: Meta's guidance is 30 degree snap turns, and the eye
// heights are the usual adult numbers. Both are parameters, so a profile can move them.
constexpr float kSnapStepDegrees = 30.0f;
constexpr float kStandingEyeInches = 66.0f;
constexpr float kSeatedEyeInches = 42.0f;

struct State {
    float yaw = 0;             // accumulated turn of the player, in degrees
    Vec3 anchor{};             // tracking-space point that maps to the world origin
    float heading = 0;         // tracking-space heading that maps to world yaw 0
    float verticalOffset = 0;  // stance offset in inches, applied to Y
    bool seated = false;
};

struct Pose {
    Vec3 position;
    float yaw;
};

// (-180, 180]. Non-finite input becomes 0 rather than propagating: nothing below can act on
// a NaN yaw.
inline float NormalizeDegrees(float degrees) {
    if (!std::isfinite(degrees)) return 0.0f;
    float value = std::fmod(degrees, 360.0f);
    if (value <= -180.0f) value += 360.0f;
    if (value > 180.0f) value -= 360.0f;
    return value;
}

inline bool Finite(const Vec3& value) {
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z);
}

// Rotate in the horizontal plane, Y unchanged.
inline Vec3 RotateYaw(const Vec3& position, float degrees) {
    if (!Finite(position) || !std::isfinite(degrees)) return position;
    const float radians = degrees * 0.017453292519943295f;
    const float cosine = std::cos(radians);
    const float sine = std::sin(radians);
    return {position.x * cosine - position.z * sine, position.y,
            position.x * sine + position.z * cosine};
}

// A discrete turn, as used by a controller button. direction is -1, 0 or 1; anything else is
// rejected instead of being clamped, because a stray value there means a broken binding.
inline bool SnapTurn(State& state, int direction, float step = kSnapStepDegrees) {
    if (direction < -1 || direction > 1) return false;
    if (!std::isfinite(step) || step <= 0.0f || step > 180.0f) return false;
    state.yaw = NormalizeDegrees(state.yaw + static_cast<float>(direction) * step);
    return true;
}

// Continuous turn from a stick. Clamped per frame so a long stall cannot spin the player by
// an unbounded angle when the frame time finally arrives.
inline bool Turn(State& state, float degreesPerSecond, float deltaSeconds,
                 float maxDegreesPerFrame = 15.0f) {
    if (!std::isfinite(degreesPerSecond) || !std::isfinite(deltaSeconds) ||
        !std::isfinite(maxDegreesPerFrame)) return false;
    if (deltaSeconds <= 0.0f || maxDegreesPerFrame <= 0.0f) return false;
    const float requested = degreesPerSecond * deltaSeconds;
    const float clamped = std::max(-maxDegreesPerFrame, std::min(maxDegreesPerFrame, requested));
    state.yaw = NormalizeDegrees(state.yaw + clamped);
    return true;
}

// Put the player at the origin facing world-forward: remember where they stand and which way
// they look, and drop any accumulated turn. Their height is untouched.
inline bool Recenter(State& state, const Vec3& head, float headYawDegrees) {
    if (!Finite(head) || !std::isfinite(headYawDegrees)) return false;
    state.anchor = {head.x, 0.0f, head.z};
    state.heading = NormalizeDegrees(headYawDegrees);
    state.yaw = 0;
    return true;
}

// Seated maps the eye height the user has now onto the seated target, so the avatar sits at
// table height instead of standing up. Standing removes the offset again.
inline bool SetStance(State& state, bool seated, float currentEyeInches,
                      float standingEyeInches = kStandingEyeInches,
                      float seatedEyeInches = kSeatedEyeInches) {
    if (!std::isfinite(currentEyeInches) || !std::isfinite(standingEyeInches) ||
        !std::isfinite(seatedEyeInches)) return false;
    if (currentEyeInches <= 0.0f) return false;
    state.seated = seated;
    state.verticalOffset = seated ? seatedEyeInches - currentEyeInches : 0.0f;
    return true;
}

// Head pose in tracking space -> pose in the playspace. Turning rotates the player about the
// recentre anchor, so walking around after a recentre keeps its scale. False leaves `out`
// untouched.
inline bool Apply(const State& state, const Snapshot& head, Pose& out) {
    if (!Finite(head.position) || !std::isfinite(head.angle.yaw) ||
        !std::isfinite(state.yaw) || !std::isfinite(state.verticalOffset) ||
        !std::isfinite(state.heading) || !Finite(state.anchor))
        return false;
    const Vec3 relative{head.position.x - state.anchor.x, 0.0f,
                        head.position.z - state.anchor.z};
    const Vec3 rotated = RotateYaw(relative, state.heading + state.yaw);
    out.position = {rotated.x, head.position.y + state.verticalOffset, rotated.z};
    out.yaw = NormalizeDegrees(head.angle.yaw - state.heading + state.yaw);
    return true;
}

}  // namespace GquestPlayspace
