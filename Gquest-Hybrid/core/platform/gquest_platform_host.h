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
    bool valid = false;  // the head pose was converted and may be published
    GquestPlayspace::Pose head{};
    GquestPlayspace::Pose hands[kHandCount]{};
    bool handValid[kHandCount]{false, false};
};

// One core frame: poll the backend, convert head and both hands through the playspace, and
// refuse the frame rather than publish a half-converted pose. A refused head invalidates the
// whole frame, because hands are only meaningful relative to it.
//
// This is the first caller of GquestPlayspace::Apply. Until now the playspace math was only
// exercised by its own test; nothing on the device calls this yet - that arrives with the
// host, which is gate G2.
inline FrameOutput GquestStepFrame(IPlatformHost& host, GquestPlayspace::State& playspace) {
    FrameOutput output{};
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
