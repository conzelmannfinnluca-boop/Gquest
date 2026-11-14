// Is this address range readable in the current process?
//
// This is the guard in front of every pinned data access and every native patch. A false
// "yes" turns a checked failure into a write into foreign memory, which is why the
// arithmetic is checked instead of assumed and why the whole range has to sit inside one
// readable mapping: a span across two mappings is refused, because no caller can act on
// half a buffer.
//
// Split out of the bridge so it can be driven on a host: /proc/self/maps exists there too,
// and mprotect makes every boundary reachable in a test.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>

static bool GquestReadableMemory(const void* address, std::size_t length) {
    const std::uintptr_t begin = reinterpret_cast<std::uintptr_t>(address);
    if (begin == 0) return false;
    // begin + length must not wrap: a wrapped end would look like a tiny range and could
    // pass the containment check below.
    if (length > UINTPTR_MAX - begin) return false;
    const std::uintptr_t end = begin + length;
    FILE* maps = std::fopen("/proc/self/maps", "r");
    if (!maps) return false;
    char line[512];
    char permissions[5];
    bool readable = false;
    while (std::fgets(line, sizeof(line), maps)) {
        unsigned long long low = 0, high = 0;
        permissions[0] = '\0';
        if (std::sscanf(line, "%llx-%llx %4s", &low, &high, permissions) != 3) continue;
        if (permissions[0] != 'r') continue;
        // begin < high as well: a zero-length range must still start inside the mapping,
        // otherwise the address just past a readable page would count as readable.
        if (static_cast<unsigned long long>(begin) >= low &&
            static_cast<unsigned long long>(begin) < high &&
            static_cast<unsigned long long>(end) <= high) {
            readable = true;
            break;
        }
    }
    std::fclose(maps);
    return readable;
}
