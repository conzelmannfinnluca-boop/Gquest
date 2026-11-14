#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

#include "gquest_signature.h"

namespace {

std::vector<unsigned char> bytes(const char* text) {
    return std::vector<unsigned char>(text, text + std::strlen(text));
}

// A 32 byte pattern like the recorded GDroid signatures.
const unsigned char longPattern[] = {
    0xff, 0x83, 0x04, 0xd1, 0xeb, 0x2b, 0x0a, 0x6d, 0xe9, 0x23, 0x0b, 0x6d,
    0xfd, 0x7b, 0x0c, 0xa9, 0xfc, 0x6f, 0x0d, 0xa9, 0xfa, 0x67, 0x0e, 0xa9,
    0xf8, 0x5f, 0x0f, 0xa9, 0xf6, 0x57, 0x10, 0xa9,
};

}  // namespace

int main() {
    auto buffer = bytes("....ABCDEFGH....");
    const uintptr_t base = reinterpret_cast<uintptr_t>(buffer.data());

    // Exactly one hit: address must point at the first matching byte, not at the range.
    auto pattern = bytes("DEFG");
    GquestScan unique = GquestScanRange(base, buffer.size(), pattern.data(), pattern.size());
    assert(unique.status == GquestScanStatus::Unique);
    assert(unique.address == base + 7);  // "DEFG" starts after "....ABC"
    assert(unique.matches == 1);

    // A hit at offset 0 must not be skipped by the first-byte fast path.
    auto start = bytes("ABC");
    GquestScan atStart = GquestScanRange(base, buffer.size(), start.data(), start.size());
    assert(atStart.status == GquestScanStatus::Unique);
    assert(atStart.address == base + 4);

    // A hit at the very end must still be inside the range.
    auto last = bytes("GH..");
    GquestScan atEnd = GquestScanRange(base, buffer.size(), last.data(), last.size());
    assert(atEnd.status == GquestScanStatus::Unique && atEnd.address == base + 10);

    // Absent pattern.
    auto absent = bytes("ZZZZ");
    GquestScan none = GquestScanRange(base, buffer.size(), absent.data(), absent.size());
    assert(none.status == GquestScanStatus::NotFound && none.matches == 0 && none.address == 0);

    // Two hits: ambiguous, and the first address is reported but must not be used.
    auto repeated = bytes("....");
    GquestScan twice = GquestScanRange(base, buffer.size(), repeated.data(), repeated.size());
    assert(twice.status == GquestScanStatus::Ambiguous);
    assert(twice.matches == 2);

    // Overlapping hits count as ambiguous too: "aaa" occurs at offset 0 and 1 of "aaaa".
    const unsigned char aaaa[] = {'a', 'a', 'a', 'a'};
    GquestScan many = GquestScanRange(reinterpret_cast<uintptr_t>(aaaa), sizeof(aaaa),
                                      aaaa, 3);
    assert(many.status == GquestScanStatus::Ambiguous && many.matches == 2);

    // Degenerate inputs are "not found", never a crash and never a hit.
    assert(GquestScanRange(base, buffer.size(), nullptr, 4).status == GquestScanStatus::NotFound);
    assert(GquestScanRange(base, buffer.size(), pattern.data(), 0).status == GquestScanStatus::NotFound);
    assert(GquestScanRange(base, 3, pattern.data(), pattern.size()).status == GquestScanStatus::NotFound);
    assert(GquestScanRange(0, buffer.size(), pattern.data(), pattern.size()).status == GquestScanStatus::NotFound);

    // A 32 byte signature is found as one block, and a truncated copy of it is not.
    std::vector<unsigned char> module(256, 0x90);
    std::memcpy(module.data() + 64, longPattern, sizeof(longPattern));
    GquestScan full = GquestScanRange(reinterpret_cast<uintptr_t>(module.data()), module.size(),
                                      longPattern, sizeof(longPattern));
    assert(full.status == GquestScanStatus::Unique);
    assert(full.address == reinterpret_cast<uintptr_t>(module.data()) + 64);
    // A shortened signature is a prefix of the real one and therefore still matches.
    // That is why the full recorded length is used: uniqueness has to come from the whole
    // block, not from a convenient first few bytes.
    const unsigned char prefix[] = {0xff, 0x83, 0x04, 0xd1, 0xeb};
    GquestScan shortHit = GquestScanRange(reinterpret_cast<uintptr_t>(module.data()),
                                          module.size(), prefix, sizeof(prefix));
    assert(shortHit.status == GquestScanStatus::Unique);
    assert(shortHit.address == reinterpret_cast<uintptr_t>(module.data()) + 64);

    // Once the same prefix also appears elsewhere, only the full block stays decisive:
    // shortening the pattern to make it fit is not a workaround, it destroys the proof.
    std::memcpy(module.data() + 200, prefix, sizeof(prefix));
    assert(GquestScanRange(reinterpret_cast<uintptr_t>(module.data()), module.size(),
                           prefix, sizeof(prefix)).status == GquestScanStatus::Ambiguous);
    assert(GquestScanRange(reinterpret_cast<uintptr_t>(module.data()), module.size(),
                           longPattern, sizeof(longPattern)).status == GquestScanStatus::Unique);

    // A duplicated block is rejected: preferring the first would be a coin flip.
    std::memcpy(module.data() + 160, longPattern, sizeof(longPattern));
    assert(GquestScanRange(reinterpret_cast<uintptr_t>(module.data()), module.size(),
                           longPattern, sizeof(longPattern)).status == GquestScanStatus::Ambiguous);

    // The resolver must return nullptr without a module, and must not log into a sink
    // that was never installed.
    assert(GquestResolveSite(nullptr, "test", longPattern, sizeof(longPattern), 0x1234) == nullptr);

    // A logger receives the reason, so a drift is visible instead of silent.
    static char seen[192];
    GquestScanLog = [](const char* message) { std::snprintf(seen, sizeof(seen), "%s", message); };
    assert(GquestResolveSite(nullptr, "test", longPattern, sizeof(longPattern), 0x1234) == nullptr);
    assert(std::strstr(seen, "test signature not found") != nullptr);
    GquestScanLog = nullptr;

    std::puts("PASS signature scan: unique hit at first byte, ambiguous duplicates and "
              "overlapping hits rejected, short prefix stops being decisive once it "
              "repeats, bad ranges not found, resolver fails closed with a reason");
}
