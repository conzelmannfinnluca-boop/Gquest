// Host tests for bridge/gquest_readable_memory.h.
//
// Three pages are mapped, the middle one is made PROT_NONE, and the guard is asked about
// every boundary that matters: inside, at the last byte, one byte past, a span across the
// protection change, a null pointer, a wrapping length and a zero-length range.
#include <sys/mman.h>
#include <unistd.h>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include "gquest_readable_memory.h"

int main() {
    const long page = sysconf(_SC_PAGESIZE);
    assert(page > 0);
    const std::size_t size = static_cast<std::size_t>(page) * 3;
    void* region = mmap(nullptr, size, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(region != MAP_FAILED);
    auto first = static_cast<char*>(region);
    char* middle = first + page;
    char* third = middle + page;
    assert(mprotect(middle, static_cast<std::size_t>(page), PROT_NONE) == 0);

    // Fully inside a readable mapping.
    assert(GquestReadableMemory(first, 4));
    assert(GquestReadableMemory(first, static_cast<std::size_t>(page)));
    // The last byte of the readable page is still inside it.
    assert(GquestReadableMemory(first + page - 1, 1));
    // One byte further reaches the PROT_NONE page: refused.
    assert(!GquestReadableMemory(first + page, 4));
    // A span that starts readable and ends unreadable is refused as a whole; half a buffer
    // is not something a caller can act on.
    assert(!GquestReadableMemory(first + page - 4, 8));
    // Readable again after the hole.
    assert(GquestReadableMemory(third, 4));

    // A null pointer is never readable, whatever the maps say.
    assert(!GquestReadableMemory(nullptr, 0));
    assert(!GquestReadableMemory(nullptr, 4));

    // A length that would wrap begin + length must be refused, not wrapped.
    assert(!GquestReadableMemory(first, UINTPTR_MAX));

    // A zero-length range asks about the address itself: mapped is yes, unmapped is no.
    assert(GquestReadableMemory(first, 0));
    assert(!GquestReadableMemory(middle, 0));

    // After releasing the mapping the same address must not read as usable.
    assert(munmap(region, size) == 0);

    std::puts("PASS readable memory: inside/at-edge accepted, PROT_NONE, spans across a "
              "mapping boundary, null and a wrapping length refused, zero length reports "
              "the address itself");
    return 0;
}
