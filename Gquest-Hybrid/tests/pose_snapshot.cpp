// Direct tests for bridge/gquest_pose_snapshot.h, plus a fake pose source that delivers 60
// frames without OpenXR, Android or the engine.
//
// Until now these rules were only reachable through the Lua bindings in vr_lua.cpp, where a
// failure could come from the bindings as easily as from the arithmetic. The expected
// numbers are the ones that test already pins, so both paths stay in agreement.
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include "gquest_pose_snapshot.h"

namespace {

constexpr std::size_t kPositionOffset = 8;    // head position inside the snapshot
constexpr std::size_t kQuaternionOffset = 20;

void WritePose(unsigned char* snapshot, const float* position, const float* orientation) {
    std::memcpy(snapshot + kPositionOffset, position, sizeof(float) * 3);
    std::memcpy(snapshot + kQuaternionOffset, orientation, sizeof(float) * 4);
}

float QuaternionNormSquared(const float* q) {
    return q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3];
}

// Deterministic stand-in for the XR input: a yaw ramp and a moving position, with two
// deliberately broken frames in the middle.
struct FakeSource {
    int frames = 0;
    int valid = 0;
    int rejected = 0;
    bool Next(unsigned char* snapshot) {
        const float t = static_cast<float>(frames);
        // In this convention a rotation about Z is the yaw angle and a rotation about Y is
        // the pitch angle, as vr_lua.cpp pins; the ramp therefore turns about Z.
        const float half = 0.5f * t * 0.1f;   // 0.1 rad per frame
        float position[3] = {0.1f * t, 1.6f, -0.2f * t};
        float orientation[4] = {0, 0, std::sin(half), std::cos(half)};
        if (frames == 17) position[0] = std::nanf("");
        if (frames == 42) orientation[0] = 1.0f;   // norm far outside the window
        WritePose(snapshot, position, orientation);
        ++frames;
        return true;
    }
};

}  // namespace

int main() {
    alignas(16) unsigned char snapshot[4288] = {};
    GquestPose::Snapshot pose{};

    // The mapping that keeps the playspace convention: metres in, inches out, Y/Z swapped.
    const float authored[3] = {1, 2, 3};
    const float identity[4] = {0, 0, 0, 1};
    WritePose(snapshot, authored, identity);
    assert(GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    assert(std::fabs(pose.position.x - 39.370098f) < 0.001f);
    assert(std::fabs(pose.position.y + 118.110294f) < 0.001f);
    assert(std::fabs(pose.position.z - 78.740196f) < 0.001f);
    assert(pose.angle.pitch == 0 && pose.angle.yaw == 0 && pose.angle.roll == 0);

    // Yaw and pitch follow the axes vr_lua.cpp pins.
    const float yawQuaternion[4] = {0, 0, 0.70710678f, 0.70710678f};
    assert(std::fabs(GquestPose::AnglesFromQuaternion(yawQuaternion).yaw - 90) < 0.001f);
    const float pitchQuaternion[4] = {0, 0.70710678f, 0, 0.70710678f};
    assert(std::fabs(GquestPose::AnglesFromQuaternion(pitchQuaternion).pitch - 90) < 0.03f);

    // Non-finite components are refused, and the output is not half-written.
    GquestPose::Snapshot untouched{};
    untouched.position = {7, 7, 7};
    const float nan = std::nanf("");
    float broken[3] = {0, 0, 0};
    broken[1] = nan;
    WritePose(snapshot, broken, identity);
    assert(!GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, untouched));
    assert(untouched.position.x == 7 && untouched.position.y == 7);
    float brokenOrientation[4] = {0, 0, 0, 1};
    brokenOrientation[3] = nan;
    WritePose(snapshot, authored, brokenOrientation);
    assert(!GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, untouched));

    // The norm window is inclusive at both ends and rejects everything outside it.
    const float tiny[4] = {0.6f, 0, 0, 0};          // squared norm 0.36
    const float large[4] = {1.3f, 0, 0, 0};         // squared norm 1.69
    WritePose(snapshot, authored, tiny);
    assert(!GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    WritePose(snapshot, authored, large);
    assert(!GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    // The window edges are not exactly representable in float (sqrt(0.5) squared lands just
    // below 0.5), so both sides of each edge are checked instead of the point itself.
    const float lower = std::sqrt(GquestPose::kMinNormSquared);
    const float upper = std::sqrt(GquestPose::kMaxNormSquared);
    const float belowLower[4] = {lower * 0.99999f, 0, 0, 0.0f};
    const float aboveLower[4] = {lower * 1.00001f, 0, 0, 0.0f};
    const float belowUpper[4] = {upper * 0.99999f, 0, 0, 0.0f};
    const float aboveUpper[4] = {upper * 1.00001f, 0, 0, 0.0f};
    WritePose(snapshot, authored, belowLower);
    assert(!GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    WritePose(snapshot, authored, aboveLower);
    assert(GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    WritePose(snapshot, authored, belowUpper);
    assert(GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    WritePose(snapshot, authored, aboveUpper);
    assert(!GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    // A zero quaternion is the case a naive implementation would happily turn into 0/0.
    const float zeroQuaternion[4] = {0, 0, 0, 0};
    WritePose(snapshot, authored, zeroQuaternion);
    assert(!GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    // A non-unit but in-window quaternion is accepted; the angles stay finite.
    const float loose[4] = {0, 0, 0.9f, 0.3f};
    assert(QuaternionNormSquared(loose) > GquestPose::kMinNormSquared);
    WritePose(snapshot, authored, loose);
    assert(GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, pose));
    assert(std::isfinite(pose.angle.pitch) && std::isfinite(pose.angle.yaw) &&
           std::isfinite(pose.angle.roll));

    // 60 frames from the fake source: two are broken, the other 58 decode, and nothing
    // non-finite ever reaches a caller.
    FakeSource source;
    float lastYaw = -1000;
    int wraps = 0;
    for (int frame = 0; frame < 60; ++frame) {
        assert(source.Next(snapshot));
        GquestPose::Snapshot decoded{};
        if (GquestPose::Decode(snapshot, kPositionOffset, kQuaternionOffset, decoded)) {
            ++source.valid;
            assert(std::isfinite(decoded.position.x) && std::isfinite(decoded.position.y) &&
                   std::isfinite(decoded.position.z));
            assert(std::isfinite(decoded.angle.pitch) && std::isfinite(decoded.angle.yaw));
            // The yaw ramp covers 6 rad, so the angle passes +/-180 once. A monotonic check
            // would fail there; the wrap itself is what to assert.
            assert(decoded.angle.yaw > -180.0f && decoded.angle.yaw <= 180.0f);
            if (lastYaw > 100.0f && decoded.angle.yaw < -100.0f) {
                ++wraps;
            } else if (wraps == 0 && lastYaw > -1000) {
                assert(decoded.angle.yaw > lastYaw);
            }
            lastYaw = decoded.angle.yaw;
        } else {
            ++source.rejected;
        }
    }
    assert(wraps == 1);
    assert(source.frames == 60);
    assert(source.rejected == 2);
    assert(source.valid == 58);

    std::puts("PASS pose snapshot: metre-to-inch mapping with Y/Z swap, yaw/pitch axes, "
              "non-finite and out-of-window quaternions refused without a half-written "
              "result, 60 fake frames with 58 valid");
    return 0;
}
