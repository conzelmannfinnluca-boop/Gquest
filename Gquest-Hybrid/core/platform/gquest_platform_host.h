// What a host must provide, and the one frame step that uses it.
//
// A host owns rendering, input, the asset filesystem and the clock; it owns no pose
// arithmetic. The core asks for those four things and produces playspace poses, which is the
// split decision E1 describes.
#pragma once
#include "gquest_i_asset_source.h"
#include "gquest_iclock.h"
#include "gquest_ilog.h"
#include "gquest_i_vr_backend.h"
#include "gquest_playspace.h"

namespace GquestPlatform {

// References are non-owning and must outlive the host object.
struct IPlatformHost {
    virtual ~IPlatformHost() = default;
    virtual IClock& Clock() = 0;
    virtual ILog& Log() = 0;
    virtual IAssetSource& Assets() = 0;
    virtual IVRBackend& Vr() = 0;
};

struct FrameOutput {
    bool valid = false;   // the head pose was converted and may be published
    bool deltaValid = false;  // this frame's time step was measured, not held
    double deltaSeconds = 0;  // the step to integrate; the previous one when deltaValid is false
    GquestPlayspace::Pose head{};
    GquestPlayspace::Pose hands[kHandCount]{};
    bool handValid[kHandCount]{false, false};
};

// One core frame: measure the time step, poll the backend, convert head and both hands
// through the playspace, and refuse the pose rather than publish a half-converted one. A
// refused head invalidates the whole frame, because hands are only meaningful relative to it.
//
// A refused time step does not invalidate the frame: the poses are still good, only the step
// is unusable, so consumers hold their previous speed instead of integrating a guess.
//
// This is the caller of GquestPlayspace::Apply and of FrameTimer; nothing on the device calls
// it yet - that arrives with the real host (gate G3).
inline FrameOutput GquestStepFrame(IPlatformHost& host, GquestPlayspace::State& playspace,
                                  FrameTimer& timer) {
    FrameOutput output{};
    // Time first: it passes whether or not a pose arrived, and a host that polls slowly must
    // not hand the next good frame a delta covering the gap as if nothing happened.
    const FrameTimer::Result timing = timer.Advance(host.Clock());
    output.deltaSeconds = timer.delta;
    output.deltaValid = timing == FrameTimer::Result::Measured;
    if (timing == FrameTimer::Result::Held)
        host.Log().Write(LogLevel::Warning, "frame clock refused");
    VrFrame frame{};
    if (!host.Vr().Poll(frame)) {
        host.Log().Write(LogLevel::Warning, "vr frame unavailable");
        return output;
    }
    if (!GquestPlayspace::Apply(playspace, frame.head, output.head)) {
        host.Log().Write(LogLevel::Warning, "head pose refused");
        return output;
    }
    output.valid = true;
    for (int hand = 0; hand < kHandCount; ++hand) {
        if (!frame.handValid[hand]) continue;
        GquestPlayspace::Pose converted{};
        if (!GquestPlayspace::Apply(playspace, frame.hands[hand], converted)) {
            host.Log().Write(LogLevel::Warning, "hand pose refused");
            continue;
        }
        output.hands[hand] = converted;
        output.handValid[hand] = true;
    }
    return output;
}

}  // namespace GquestPlatform
