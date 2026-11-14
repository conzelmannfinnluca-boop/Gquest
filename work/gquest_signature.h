// Locate patched code sites by byte signature instead of a fixed virtual address.
//
// A hardcoded VA is only valid for the exact build it was derived from. Any GDroid
// update that shifts code silently points a patch at unrelated instructions. Scanning
// for the recorded bytes makes the site self-verifying, and every failure mode here is
// fail-closed: no match or more than one match resolves to nullptr, never to a guess.
//
// The expected offset is still passed in, but only to log that a signature moved. The
// scanned address is what gets used, so a shifted build keeps working when the bytes are
// still unique.
//
// Data globals (GOT slots, BSS records) cannot be found this way; they stay pinned to the
// audited build and are guarded by the existing readability checks. See
// docs/SOURCE_ANALYSIS.md, T1.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <link.h>

enum class GquestScanStatus { NotFound, Unique, Ambiguous };

struct GquestScan {
    GquestScanStatus status = GquestScanStatus::NotFound;
    uintptr_t address = 0;
    size_t matches = 0;
};

using GquestScanLogger = void (*)(const char* message);

// Set by the bridge so a drift or an unresolved site shows up in the log. Left empty in
// tests, which must not depend on a logging sink.
static GquestScanLogger GquestScanLog = nullptr;

// Exact byte search in one contiguous range. Stops at the second hit: two candidates are
// already unusable, and stopping keeps the worst case short on a large segment.
static GquestScan GquestScanRange(uintptr_t start, size_t size,
                                  const unsigned char* pattern, size_t patternSize) {
    GquestScan scan;
    if (start == 0 || !pattern || patternSize == 0 || size < patternSize) return scan;
    const auto* bytes = reinterpret_cast<const unsigned char*>(start);
    const size_t last = size - patternSize;
    for (size_t offset = 0; offset <= last; ++offset) {
        if (bytes[offset] != pattern[0]) continue;
        if (std::memcmp(bytes + offset, pattern, patternSize) != 0) continue;
        if (scan.matches == 0) scan.address = start + offset;
        ++scan.matches;
        if (scan.matches > 1) {
            scan.status = GquestScanStatus::Ambiguous;
            return scan;
        }
    }
    if (scan.matches == 1) scan.status = GquestScanStatus::Unique;
    return scan;
}

struct GquestScanRequest {
    uintptr_t base = 0;
    const unsigned char* pattern = nullptr;
    size_t size = 0;
    GquestScan result;
};

// Only file-backed executable segments are searched. .data and .bss can hold a copy of a
// code sequence (constant pools, tables) and would turn a unique signature into a false
// ambiguity, which would disable the patch for no reason.
static int GquestScanSegments(struct dl_phdr_info* info, size_t, void* data) {
    auto* request = static_cast<GquestScanRequest*>(data);
    if (static_cast<uintptr_t>(info->dlpi_addr) != request->base) return 0;
    for (int index = 0; index < info->dlpi_phnum; ++index) {
        const ElfW(Phdr) & header = info->dlpi_phdr[index];
        if (header.p_type != PT_LOAD || !(header.p_flags & PF_X) || header.p_filesz == 0) continue;
        const GquestScan hit = GquestScanRange(request->base + header.p_vaddr,
                                               static_cast<size_t>(header.p_filesz),
                                               request->pattern, request->size);
        if (hit.status == GquestScanStatus::NotFound) continue;
        if (hit.status == GquestScanStatus::Ambiguous || request->result.matches != 0) {
            request->result.status = GquestScanStatus::Ambiguous;
            request->result.matches += hit.matches;
            return 1;
        }
        request->result = hit;
    }
    return 0;
}

// Search the whole loaded module for exactly one occurrence of the pattern.
static GquestScan GquestScanExecutable(void* base, const unsigned char* pattern, size_t patternSize) {
    GquestScanRequest request;
    request.base = reinterpret_cast<uintptr_t>(base);
    request.pattern = pattern;
    request.size = patternSize;
    if (request.base == 0) return request.result;
    dl_iterate_phdr(GquestScanSegments, &request);
    return request.result;
}

// Resolve one patched site. Returns nullptr when the site cannot be identified with
// certainty; callers must treat that as "do nothing" and say so in the log.
static unsigned char* GquestResolveSite(void* base, const char* name,
                                        const unsigned char* signature, size_t length,
                                        uintptr_t expectedOffset) {
    const GquestScan scan = GquestScanExecutable(base, signature, length);
    char message[192];
    if (scan.status != GquestScanStatus::Unique) {
        std::snprintf(message, sizeof(message), "%s signature %s (matches=%zu); no change",
                      name,
                      scan.status == GquestScanStatus::NotFound ? "not found" : "ambiguous",
                      scan.matches);
        if (GquestScanLog) GquestScanLog(message);
        return nullptr;
    }
    const uintptr_t offset = scan.address - reinterpret_cast<uintptr_t>(base);
    if (offset != expectedOffset) {
        std::snprintf(message, sizeof(message),
                      "%s moved from 0x%zx to 0x%zx; using the scanned site", name,
                      static_cast<size_t>(expectedOffset), static_cast<size_t>(offset));
        if (GquestScanLog) GquestScanLog(message);
    }
    return reinterpret_cast<unsigned char*>(scan.address);
}
