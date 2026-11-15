// Logging sink for the core.
//
// The core does not decide where text goes; the host does. That keeps the same frame code
// usable in the game (print), in a test (captured records) and on a host without a console.
#pragma once
#include "gquest_platform_types.h"

namespace GquestPlatform {

// `message` is only valid for the duration of the call. A sink that keeps it has to copy.
struct ILog {
    virtual ~ILog() = default;
    virtual void Write(LogLevel level, const char* message) = 0;
};

// Whether a record at `level` passes a sink's `threshold`. Kept here so filtering cannot be
// written with the comparison the wrong way round in one host and right in the other.
inline bool GquestLogAtLeast(LogLevel level, LogLevel threshold) {
    return static_cast<int>(level) >= static_cast<int>(threshold);
}

}  // namespace GquestPlatform
