// Shared value types for the platform interfaces.
//
// Engine-free by construction: only standard headers and the pose snapshot, which is already
// host-tested. Nothing here knows about OpenXR, Android or the Source engine, which is the
// whole point of the split decided as E1 in PROJECT_STATUS.md - a header that pulled an
// engine type in would make the core untestable on a host and the decision worthless.
#pragma once
#include "gquest_pose_snapshot.h"

namespace GquestPlatform {

enum class LogLevel { Trace = 0, Info = 1, Warning = 2, Error = 3 };

inline const char* GquestLogLevelName(LogLevel level) {
    switch (level) {
        case LogLevel::Trace: return "trace";
        case LogLevel::Info: return "info";
        case LogLevel::Warning: return "warning";
        case LogLevel::Error: return "error";
    }
    return "unknown";
}

// Index order is fixed: 0 is left, 1 is right. The native bindings already use that order,
// so changing it here would swap the hands everywhere at once.
enum class Hand { Left = 0, Right = 1 };
constexpr int kHandCount = 2;

// One frame as the backend reports it. Poses are in the tracking space the pose snapshot
// uses (inches, Y up); the playspace conversion happens in the core, not here.
struct VrFrame {
    GquestPose::Snapshot head{};
    GquestPose::Snapshot hands[kHandCount]{};
    bool handValid[kHandCount]{false, false};
};

// A frame longer than this is a stall, not a frame. Clamping keeps one hitch from moving the
// tracked position by an unbounded step; half a second is already far beyond a dropped frame
// at any rate this project targets.
constexpr double kMaxFrameSeconds = 0.5;

// Haptic limits. Values outside them are never forwarded to the runtime: the native call
// takes plain floats and imposes no range of its own.
constexpr float kMaxHapticSeconds = 2.0f;
constexpr float kMinHapticHz = 1.0f;
constexpr float kMaxHapticHz = 1000.0f;
constexpr float kMaxHapticAmplitude = 1.0f;

}  // namespace GquestPlatform
