// Read access to the content root.
//
// Paths are relative to that root. The policy below is the same one the content installer
// applies to a manifest line: whichever path the installer refuses must not become readable
// through this interface, or a rejected listing entry could still be opened by the core.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>
#include "gquest_platform_types.h"

namespace GquestPlatform {

// Non-empty, not absolute, no ".." anywhere, no carriage return. Kept identical to the rules
// in gquest_content_install.h on purpose; the boundary test compares the two so they cannot
// drift apart.
inline bool GquestAssetPathAllowed(const char* path) {
    if (!path || !*path) return false;
    if (path[0] == '/') return false;
    if (std::strstr(path, "..")) return false;
    if (std::strchr(path, '\r')) return false;
    return true;
}

struct IAssetSource {
    virtual ~IAssetSource() = default;
    // False for a refused path and for a missing file.
    virtual bool Exists(const char* relativePath) = 0;
    // False - with `out` untouched - for a refused path, a missing file or a file larger
    // than maxBytes. A truncated read would be indistinguishable from a valid file, which is
    // the failure this signature exists to prevent.
    virtual bool Read(const char* relativePath, std::size_t maxBytes,
                      std::vector<std::uint8_t>& out) = 0;
};

}  // namespace GquestPlatform
