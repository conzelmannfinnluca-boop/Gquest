// Gate G2: the core driven by a fake host, with no engine, no XR session and no APK.
//
// Two things are checked here. First, that a run of 60 frames produces the poses the playspace
// rules promise - including a snap turn, a recentre and the seated offset in the middle of the
// run - and that the frames it must refuse are refused and logged. Second, that the content
// installation keeps the contract the device loop implements: judged before the first file is
// written, idempotent by size, lua/ always rewritten, and the first bad entry stops the run.
//
// Engine-free by construction: standard headers, core headers and the installer's rules only.
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "gquest_fake_host.h"

using namespace GquestFake;
using GquestPlatform::FrameOutput;
using GquestPlatform::Hand;
using GquestPlatform::LogLevel;

namespace {

Bytes MakeBytes(std::size_t count, std::uint8_t value) { return Bytes(count, value); }

GquestPose::Snapshot HeadAt(float x, float z, float yaw, float y = 62.0f) {
    GquestPose::Snapshot pose{};
    pose.position = {x, y, z};
    pose.angle = {0.0f, yaw, 0.0f};
    return pose;
}

bool Near(double actual, double expected, double tolerance = 0.001) {
    return std::fabs(actual - expected) <= tolerance;
}

double Distance2D(const GquestPlayspace::Pose& a, const GquestPlayspace::Pose& b) {
    const double dx = static_cast<double>(a.position.x) - b.position.x;
    const double dz = static_cast<double>(a.position.z) - b.position.z;
    return std::sqrt(dx * dx + dz * dz);
}

}  // namespace

int main() {
    // --- Content installation -------------------------------------------------------------
    Assets assets;
    assets.staged["lua/a.lua"] = MakeBytes(4, 'a');
    assets.staged["models/b.mdl"] = MakeBytes(8, 'b');
    assets.staged["sound/c.wav"] = MakeBytes(12, 'c');
    const std::string listing = "4\tlua/a.lua\n8\tmodels/b.mdl\n12\tsound/c.wav\n";

    Assets::InstallResult first = assets.InstallManifest(listing);
    assert(first.ok && first.installed == 3 && first.existing == 0);
    assert(first.writtenBytes == 24 && assets.installed.size() == 3);

    // A second run installs nothing new, except the lua/ file, which is always rewritten - the
    // device loop does the same, so an updated Lua file cannot be skipped by a size match.
    Assets::InstallResult second = assets.InstallManifest(listing);
    assert(second.ok && second.installed == 1 && second.existing == 2);
    assert(second.writtenBytes == 4);

    // A rewritten lua/ file really is the new content.
    assets.staged["lua/a.lua"] = MakeBytes(4, 'z');
    assert(assets.InstallManifest("4\tlua/a.lua\n").ok);
    Bytes buffer;
    assert(assets.Read("lua/a.lua", 4, buffer) && buffer.size() == 4 && buffer[0] == 'z');

    // A shipped file that does not match the listed size stops the run at that entry.
    assets.staged["models/d.mdl"] = MakeBytes(5, 'd');
    Assets::InstallResult wrongSize = assets.InstallManifest("6\tmodels/d.mdl\n");
    assert(!wrongSize.ok && wrongSize.sizeMismatch);
    assert(wrongSize.failedPath == "models/d.mdl" && wrongSize.installed == 0);
    assert(assets.installed.count("models/d.mdl") == 0);

    // A listed file that was never shipped stops it too, without claiming a size problem.
    Assets::InstallResult missing = assets.InstallManifest("3\tmodels/missing.mdl\n");
    assert(!missing.ok && !missing.sizeMismatch && missing.failedPath == "models/missing.mdl");

    // The listing is judged before anything is written: a rejected path writes nothing at all.
    const std::size_t before = assets.installed.size();
    Assets::InstallResult absolute = assets.InstallManifest("4\t/etc/passwd\n");
    assert(!absolute.ok && absolute.manifestError == GquestManifestError::AbsolutePath);
    assert(absolute.installed == 0 && assets.installed.size() == before);
    Assets::InstallResult traversal = assets.InstallManifest("4\tlua/../../escape.lua\n");
    assert(!traversal.ok && traversal.manifestError == GquestManifestError::ParentTraversal);
    Assets::InstallResult empty = assets.InstallManifest("");
    assert(!empty.ok && empty.installed == 0 && assets.installed.size() == before);

    // What was installed is readable through the interface, and only that.
    assert(assets.Exists("models/b.mdl") && !assets.Exists("models/d.mdl"));
    assert(!assets.Read("models/b.mdl", 7, buffer) && buffer.size() == 4);
    assert(assets.Read("models/b.mdl", 8, buffer) && buffer.size() == 8);
    assert(!assets.Read("/etc/passwd", 64, buffer));

    // --- 60 frames -----------------------------------------------------------------------
    Host host;
    GquestPlayspace::State playspace{};
    const float frameSeconds = 1.0f / 72.0f;

    // Head walks along X, yaw fixed at 37; two frames carry a broken head, hands are valid on
    // even frames only.
    host.vr.frames.resize(60);
    for (int index = 0; index < 60; ++index) {
        GquestPose::Snapshot head = HeadAt(10.0f + 2.0f * index, -4.0f, 37.0f);
        host.vr.frames[index].head = head;
        host.vr.frames[index].hands[0] =
            HeadAt(head.position.x, head.position.z + 14.0f, 37.0f);
        host.vr.frames[index].handValid[0] = (index % 2 == 0);
        if (index == 10 || index == 40) host.vr.frames[index].head.position.x = std::nanf("");
    }

    const RunResult run = RunFrames(host, playspace, 62, frameSeconds, [&](int index, const FrameOutput*) {
        if (index == 5) {
            // One valid haptic and one that must be refused before it reaches the runtime.
            host.vr.Haptic(Hand::Right, 0.1f, 160.0f, 0.5f);
            host.vr.Haptic(Hand::Right, 0.1f, 0.0f, 0.5f);
        }
        if (index == 20) GquestPlayspace::SnapTurn(playspace, 1, 30.0f);
        if (index == 30)
            GquestPlayspace::Recenter(playspace, host.vr.frames[index].head.position, 37.0f);
        if (index == 50) GquestPlayspace::SetStance(playspace, true, 62.0f);
    });

    // 60 scripted frames, two of them with a broken head; the last two frames have no data at
    // all, which the core has to survive as well.
    assert(run.outputs.size() == 62);
    assert(run.valid == 58 && run.rejected == 4);
    assert(run.finite);
    assert(run.handsPublished == 28);  // even frames 0..58, minus the two broken heads
    assert(std::fabs(run.elapsed - 62.0 / 72.0) < 0.0001);
    assert(host.vr.hapticHands.size() == 1);
    assert(host.log.Count(LogLevel::Warning) == 4);  // two heads, two missing frames
    assert(host.log.Has(LogLevel::Warning, "head pose refused"));
    assert(host.log.Has(LogLevel::Warning, "vr frame unavailable"));

    // Before the recentre the playspace is the identity: the output is the tracking pose.
    assert(std::fabs(run.outputs[1].head.position.x - 12.0f) < 0.001f);
    assert(std::fabs(run.outputs[1].head.yaw - 37.0f) < 0.001f);

    // The snap turn is visible on the next frame: 37 degrees of head plus 30 of turn.
    assert(std::fabs(run.outputs[21].head.yaw - 67.0f) < 0.001f);

    // After the recentre at frame 30 the head sits on the axis, faces forward, keeps its height.
    assert(std::fabs(run.outputs[30].head.position.x) < 0.001f);
    assert(std::fabs(run.outputs[30].head.position.z) < 0.001f);
    assert(std::fabs(run.outputs[30].head.position.y - 62.0f) < 0.001f);
    assert(std::fabs(run.outputs[30].head.yaw) < 0.001f);

    // Walking after the recentre keeps its distance; the direction stays rotated by the
    // heading that was current at the recentre, so the distance is the invariant to check and
    // a coordinate would only pin one heading.
    const double walkedX = run.outputs[31].head.position.x;
    const double walkedZ = run.outputs[31].head.position.z;
    assert(std::fabs(std::sqrt(walkedX * walkedX + walkedZ * walkedZ) - 2.0) < 0.01);
    assert(std::fabs(Distance2D(run.outputs[32].hands[0], run.outputs[32].head) - 14.0) < 0.01);

    // Seated lowers the avatar onto the seated eye height, standing would restore it.
    assert(std::fabs(run.outputs[50].head.position.y - 42.0f) < 0.001f);

    // Nothing was published for the refused frames.
    assert(!run.outputs[10].valid && !run.outputs[40].valid);
    assert(!run.outputs[60].valid && !run.outputs[61].valid);

    // --- Bad conditions -------------------------------------------------------------------
    // Jitter, a dropped sample, a frozen clock, a ten second jump backwards, a 20 ms step
    // right after it, a three second stall and a NaN reading — with a continuous turn driven
    // from the measured step. None of it may reach the playspace as if it were a normal frame.
    Host rough;
    GquestPlayspace::State roughSpace{};
    rough.vr.frames.resize(9);
    for (int index = 0; index < 9; ++index)
        rough.vr.frames[index].head = HeadAt(0.0f, 0.0f, 0.0f);
    rough.vr.available = {1, 1, 0, 1, 1, 1, 1, 1, 1};  // the sample at frame 2 never arrived
    std::vector<double> deltas = {1.0 / 72.0, 1.0 / 60.0, 1.0 / 90.0, 0.0, -10.0,
                                  0.02,       3.0,        std::nan(""), 1.0 / 72.0};
    const RunResult roughRun = RunFrames(
        rough, roughSpace, 9, 1.0 / 72.0,
        [&](int index, const FrameOutput* previous) {
            // 180 deg/s of stick: without the per-frame clamp a three second stall would turn
            // the player by 540 degrees in a single step.
            if (previous && previous->deltaValid)
                GquestPlayspace::Turn(roughSpace, 180.0f,
                                      static_cast<float>(previous->deltaSeconds), 15.0f);
            if (index == 8) rough.clock.Set(3.02);  // the clock recovers
        },
        &deltas);

    assert(roughRun.outputs.size() == 9);
    assert(roughRun.valid == 8 && roughRun.rejected == 1);  // one dropped sample
    assert(roughRun.finite);
    assert(!roughRun.outputs[0].deltaValid);  // the first sample only starts the timer
    assert(roughRun.outputs[1].deltaValid);   // jitter is still a measurement
    assert(!roughRun.outputs[3].deltaValid);  // frozen clock
    assert(!roughRun.outputs[4].deltaValid);  // ten seconds backwards
    // The 20 ms step right after the jump is the point of the resync: without it the old,
    // higher timestamp would make every following frame look backwards for ten seconds.
    assert(roughRun.outputs[5].deltaValid && Near(roughRun.outputs[5].deltaSeconds, 0.02));
    assert(roughRun.outputs[6].deltaValid);
    assert(Near(roughRun.outputs[6].deltaSeconds, GquestPlatform::kMaxFrameSeconds));
    assert(!roughRun.outputs[7].deltaValid);  // NaN reading
    assert(roughRun.outputs[8].deltaValid);   // recovered
    assert(rough.log.Count(LogLevel::Warning) == 4);  // three clocks, one dropped frame

    // A dropped sample publishes no pose at all, so its fields stay zero.
    assert(!roughRun.outputs[2].valid && roughRun.outputs[2].head.yaw == 0);
    // The jittered steps move the player by exactly what was measured, the frozen and
    // backwards frames move nothing, and the stall costs one clamped step instead of 90
    // degrees. Each turn uses the step measured on the frame before it.
    assert(Near(roughRun.outputs[3].head.yaw, 5.0));
    assert(Near(roughRun.outputs[4].head.yaw, 5.0));
    assert(Near(roughRun.outputs[5].head.yaw, 5.0));
    assert(Near(roughRun.outputs[6].head.yaw, 8.6));
    assert(Near(roughRun.outputs[7].head.yaw, 23.6));
    assert(Near(roughRun.outputs[8].head.yaw, 23.6));

    std::puts("PASS fake host: 60 frames driven without an engine - snap turn, recentre and "
              "seated offset visible in the published poses, broken heads and missing frames "
              "refused and logged, hands dropped alone, one valid and one refused haptic; "
              "content installation judged before writing, idempotent by size, lua/ always "
              "rewritten, first bad entry stops the run; under jitter, a dropped sample, a "
              "frozen and a backwards clock, a stall and a NaN reading the poses stay finite "
              "and the turn only ever moves by measured, clamped steps");
    return 0;
}
