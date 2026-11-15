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

}  // namespace GquestPlatform
