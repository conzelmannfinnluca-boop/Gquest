// Host tests for bridge/gquest_playspace.h: yaw wrapping, snap and smooth turn, recentre and
// the seated/standing offset, all without a headset.
//
// The recentre cases are stated as properties rather than as expected numbers: after a
// recentre the head has to sit on the vertical axis, face forward, and keep its height. That
// is the contract a tracking provider relies on, and it stays true for any input pose.
#include <cassert>
#include <cmath>
#include <cstdio>
#include "gquest_playspace.h"

using namespace GquestPlayspace;

namespace {

bool Near(float actual, float expected, float tolerance = 0.001f) {
    return std::fabs(actual - expected) <= tolerance;
}

Snapshot HeadAt(float x, float y, float z, float yaw) {
    Snapshot head{};
    head.position = {x, y, z};
    head.angle = {0.0f, yaw, 0.0f};
    return head;
}

}  // namespace

int main() {
    // Wrapping stays in (-180, 180] and cannot drift.
    assert(NormalizeDegrees(0) == 0);
    assert(NormalizeDegrees(180) == 180);
    assert(NormalizeDegrees(-180) == 180);
    assert(NormalizeDegrees(190) == -170);
    assert(NormalizeDegrees(-190) == 170);
    assert(NormalizeDegrees(360) == 0);
    assert(NormalizeDegrees(725) == 5);
    assert(NormalizeDegrees(std::nanf("")) == 0);
    assert(NormalizeDegrees(INFINITY) == 0);

    // Rotation in the horizontal plane, height untouched.
    const Vec3 forward = RotateYaw(Vec3{1, 5, 0}, 90);
    assert(Near(forward.x, 0) && Near(forward.z, 1) && Near(forward.y, 5));
    const Vec3 back = RotateYaw(Vec3{1, 0, 0}, 180);
    assert(Near(back.x, -1) && Near(back.z, 0));

    // Snap turn: one step per press, wrapping across the seam both ways.
    State state{};
    assert(SnapTurn(state, 1));
    assert(Near(state.yaw, 30));
    assert(SnapTurn(state, 1, 60));
    assert(Near(state.yaw, 90));
    assert(SnapTurn(state, -1, 60));
    assert(Near(state.yaw, 30));
    state.yaw = 170;
    assert(SnapTurn(state, 1));          // 200 -> -160
    assert(Near(state.yaw, -160));
    assert(SnapTurn(state, -1));         // -190 -> 170
    assert(Near(state.yaw, 170));
    // Direction 0 is a no-op, not a step.
    const float before = state.yaw;
    assert(SnapTurn(state, 0, 60));
    assert(Near(state.yaw, before));
    // A broken binding is rejected instead of being clamped into a turn.
    assert(!SnapTurn(state, 2));
    assert(!SnapTurn(state, -2));
    assert(!SnapTurn(state, 1, 0));
    assert(!SnapTurn(state, 1, 181));
    assert(!SnapTurn(state, 1, std::nanf("")));
    assert(Near(state.yaw, before));

    // Smooth turn is frame-rate independent and clamped against a stall.
    State smooth{};
    assert(Turn(smooth, 90, 0.5f, 90));
    assert(Near(smooth.yaw, 45));
    assert(Turn(smooth, 90, 1.0f, 5));   // a one-second stall must not spin by 90
    assert(Near(smooth.yaw, 50));
    assert(Turn(smooth, -90, 0.5f, 90));
    assert(Near(smooth.yaw, 5));
    assert(!Turn(smooth, 90, 0));
    assert(!Turn(smooth, 90, -0.1f));
    assert(!Turn(smooth, std::nanf(""), 0.016f));

    // Recentre: head lands on the vertical axis, faces forward, keeps its height.
    State centred{};
    assert(Recenter(centred, Vec3{10, 62, -4}, 37));
    Pose pose{};
    assert(Apply(centred, HeadAt(10, 62, -4, 37), pose));
    assert(Near(pose.position.x, 0) && Near(pose.position.z, 0));
    assert(Near(pose.position.y, 62));
    assert(Near(pose.yaw, 0));
    // A second recentre from the same pose changes nothing: it is idempotent.
    assert(Recenter(centred, Vec3{10, 62, -4}, 37));
    assert(Apply(centred, HeadAt(10, 62, -4, 37), pose));
    assert(Near(pose.position.x, 0) && Near(pose.position.z, 0) && Near(pose.yaw, 0));

    // Recentre then turn: the player still faces where the turn says, at the origin.
    assert(SnapTurn(centred, 1, 90));
    assert(Apply(centred, HeadAt(10, 62, -4, 37), pose));
    assert(Near(pose.position.x, 0) && Near(pose.position.z, 0));
    assert(Near(pose.yaw, 90));

    // Walking after a recentre keeps its distance, and a turn is a rigid rotation of that
    // walk: same radius, same angular offset. Stated as an invariant instead of as a
    // coordinate, because a coordinate here would only pin one heading.
    assert(Recenter(centred, Vec3{10, 62, -4}, 37));
    assert(Apply(centred, HeadAt(10, 62, -4 + 12, 37), pose));
    const Vec3 walked = pose.position;
    assert(Near(std::sqrt(walked.x * walked.x + walked.z * walked.z), 12));
    assert(SnapTurn(centred, 1, 90));
    assert(Apply(centred, HeadAt(10, 62, -4 + 12, 37), pose));
    assert(Near(std::sqrt(pose.position.x * pose.position.x +
                          pose.position.z * pose.position.z), 12));
    const Vec3 expected = RotateYaw(walked, 90);
    assert(Near(pose.position.x, expected.x) && Near(pose.position.z, expected.z));
    assert(Near(pose.yaw, 90));

    // Every heading recentres to zero, not just the sample above.
    for (float yaw = -180; yaw <= 180; yaw += 15) {
        State any{};
        assert(Recenter(any, Vec3{3, 60, 7}, yaw));
        assert(Apply(any, HeadAt(3, 60, 7, yaw), pose));
        assert(Near(pose.position.x, 0) && Near(pose.position.z, 0) && Near(pose.yaw, 0));
    }

    // Seated lowers the avatar by the difference to the seated eye height; standing undoes it.
    State stance{};
    assert(SetStance(stance, true, 66));
    assert(Near(stance.verticalOffset, 42 - 66));
    assert(Apply(stance, HeadAt(0, 66, 0, 0), pose));
    assert(Near(pose.position.y, 42));
    assert(SetStance(stance, true, 52));   // a shorter player still ends up seated
    assert(Apply(stance, HeadAt(0, 52, 0, 0), pose));
    assert(Near(pose.position.y, 42));
    assert(SetStance(stance, false, 66));
    assert(Near(stance.verticalOffset, 0));
    assert(Apply(stance, HeadAt(0, 66, 0, 0), pose));
    assert(Near(pose.position.y, 66));
    // Height zero is not a person; refusing keeps the offset out of nonsense.
    assert(!SetStance(stance, true, 0));
    assert(!SetStance(stance, true, std::nanf("")));

    // A broken pose is refused and the output is not half-written.
    State live{};
    Pose untouched{};
    untouched.position = {9, 9, 9};
    untouched.yaw = 9;
    Snapshot broken = HeadAt(0, 60, 0, 0);
    broken.position.x = std::nanf("");
    assert(!Apply(live, broken, untouched));
    assert(untouched.position.x == 9 && untouched.yaw == 9);
    assert(!Recenter(live, Vec3{0, 60, std::nanf("")}, 0));
    assert(!Recenter(live, Vec3{0, 60, 0}, std::nanf("")));

    std::puts("PASS playspace: yaw wrapped into (-180,180], snap turn steps and wraps, "
              "invalid directions and steps refused, smooth turn clamped per frame, recentre "
              "puts the head on the axis facing forward at unchanged height for every "
              "heading, seated/standing offset applied and removed");
    return 0;
}
