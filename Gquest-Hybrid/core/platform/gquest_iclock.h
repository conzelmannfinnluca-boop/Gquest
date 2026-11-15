// Monotonic time for the core.
//
// Wall clock time is deliberately not part of the contract: a clock that jumps backwards
// would move the playspace backwards with it, and one that jumps by hours would move it by a
// whole session. The core only ever asks how much time passed.
#pragma once
#include <algorithm>
#include <cmath>
#include "gquest_platform_types.h"

namespace GquestPlatform {

struct IClock {
    virtual ~IClock() = default;
    virtual double NowSeconds() const = 0;
};

// Delta between two samples, clamped to kMaxFrameSeconds. False when either sample is not
// finite or time did not move forward, so the caller keeps its previous delta instead of
// integrating a zero or a negative step.
inline bool GquestFrameDelta(double previous, double now, double& out) {
    if (!std::isfinite(previous) || !std::isfinite(now)) return false;
    const double delta = now - previous;
    if (!(delta > 0.0)) return false;
    out = std::min(delta, kMaxFrameSeconds);
    return true;
}

// Keeps the previous sample and hands out the frame delta.
//
// A refused sample resyncs the timer on a finite reading, so one glitch does not blind every
// frame after it: without the resync a single backwards jump would keep the delta unusable
// until the clock caught up with the old value again.
struct FrameTimer {
    enum class Result { Started, Measured, Held };

    bool started = false;
    double last = 0;
    double delta = 0;  // last accepted delta; 0 until the first measurement

    Result Advance(IClock& clock) {
        const double now = clock.NowSeconds();
        if (!started) {
            if (!std::isfinite(now)) return Result::Held;
            started = true;
            last = now;
            delta = 0;
            return Result::Started;
        }
        double measured = 0;
        if (!GquestFrameDelta(last, now, measured)) {
            if (std::isfinite(now)) last = now;
            return Result::Held;
        }
        last = now;
        delta = measured;
        return Result::Measured;
    }
};

}  // namespace GquestPlatform
