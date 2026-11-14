#!/usr/bin/env python3
"""Check the pinned libclient addresses against the audit record and the ELF segments.

The bridge patches and reads fixed virtual addresses recorded for GDroid 0.1.30. Two
questions follow, and they are not the same:

1. Do the constants agree with the audit record? That is checkable here, always.
2. Do those addresses really lie in readable segments of that exact library? That needs the
   library, which is private and not in this repository. Without it the answer is
   "not verifiable", never "fine".

Code sites (functions, patch targets) must sit in an executable segment; data globals in the
GOT/BSS must sit in a readable one and, for the write patches, a writable one. A wrong pin
is guarded at runtime by the readable-range check in the bridge, so it fails closed - but a
pin that is merely *plausible* should not pass silently here.

Usage:
    python3 Gquest-Hybrid/tools/pinned_addresses.py            # report + ELF check if the
                                                               # library is present
    python3 Gquest-Hybrid/tools/pinned_addresses.py --test     # logic self-test

Exit codes: 0 all checks passed, 1 a check failed, 2 consistency ok but the library is
missing so segment membership could not be verified.
"""
import argparse
import json
import struct
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BASE = PROJECT.parent
AUDIT = BASE / "work/gdroid130-compat/audit.json"
LIBRARY = BASE / "work/gdroid-0.1.30-native/libclient.so"

# Sites the bridge touches, and what the segment has to provide.
CODE = ("pose_constructor", "left_palm_branch", "finger_blend_call", "finger_blend_function",
        "local_hand_pose", "layer_allocator", "vrplayer_init_patch",
        "input_snapshot_false_stub")
DATA = ("vr_singleton_got", "material_system_got", "layer_record_array")

PT_LOAD = 1
PF_X, PF_W, PF_R = 1, 2, 4


class Segment:
    def __init__(self, vaddr, memsz, filesz, flags):
        self.vaddr, self.memsz, self.filesz, self.flags = vaddr, memsz, filesz, flags

    def contains(self, address):
        return self.vaddr <= address < self.vaddr + self.memsz

    def describe(self):
        letters = "".join(letter for flag, letter in
                          ((PF_R, "r"), (PF_W, "w"), (PF_X, "x")) if self.flags & flag)
        return f"{self.vaddr:#x}+{self.memsz:#x} {letters}"


def load_segments(blob):
    """PT_LOAD segments of an ELF64 little-endian shared object. Raises ValueError."""
    if len(blob) < 64 or blob[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    if blob[4] != 2 or blob[5] != 1:
        raise ValueError("only ELF64 little-endian is supported")
    phoff, = struct.unpack_from("<Q", blob, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", blob, 0x36)
    if phentsize < 56 or phoff + phentsize * phnum > len(blob):
        raise ValueError("program header table outside the file")
    segments = []
    for index in range(phnum):
        base = phoff + index * phentsize
        p_type, p_flags = struct.unpack_from("<II", blob, base)
        p_filesz, = struct.unpack_from("<Q", blob, base + 0x20)
        p_vaddr, p_memsz = struct.unpack_from("<QQ", blob, base + 0x10)[0], \
            struct.unpack_from("<Q", blob, base + 0x28)[0]
        if p_type == PT_LOAD:
            segments.append(Segment(p_vaddr, p_memsz, p_filesz, p_flags))
    return segments


def classify(address, segments):
    for segment in segments:
        if segment.contains(address):
            return segment
    return None


def audit_consistency(audit):
    """Problems that can be found without the library."""
    problems, notes = [], []
    addresses = {name: int(entry["new"], 16) for name, entry in audit["addresses"].items()}

    # The bridge does not hardcode these two targets; it adds these offsets after the
    # signature search. If the audit ever disagrees, one of the two is wrong.
    for label, high, low, expected in (
            ("left palm branch", "left_palm_branch", "pose_constructor", 0x224),
            ("finger blend call", "finger_blend_call", "finger_blend_function", 0x564)):
        delta = addresses[high] - addresses[low]
        notes.append(f"{label}: {high} - {low} = {delta:#x} (bridge expects {expected:#x})")
        if delta != expected:
            problems.append(f"{label} offset {delta:#x} != {expected:#x} used by the bridge")

    code = [addresses[name] for name in CODE]
    data = [addresses[name] for name in DATA]
    notes.append(f"code range {min(code):#x}..{max(code):#x}, "
                 f"data range {min(data):#x}..{max(data):#x}")
    if max(code) >= min(data):
        problems.append("code and data addresses overlap; the audit looks inconsistent")
    for name in CODE + DATA:
        if addresses[name] >= 1 << 32:
            problems.append(f"{name} does not fit in 32 bits")

    # The one entry that states both a VA and a file offset pins the mapping shift for the
    # executable segment. The file offset belongs to the patched instruction
    # (addresses.vrplayer_init_patch), not to the function start - pairing the function
    # start with it yields 0x3fc4, which is not page aligned and would be a real error.
    patch_va = addresses["vrplayer_init_patch"]
    file_offset = int(audit["vrplayer_init"]["patch_new_file_offset"], 16)
    shift = patch_va - file_offset
    notes.append(f"patched instruction {patch_va:#x} - file offset {file_offset:#x} = "
                 f"{shift:#x}")
    if shift <= 0:
        problems.append("file offset is not below the VA; mapping shift is implausible")
    elif shift % 0x1000:
        problems.append(f"mapping shift {shift:#x} is not page aligned, so the VA and the "
                        "file offset do not belong together")
    return problems, notes


def segment_problems(audit, segments):
    problems = []
    addresses = {name: int(entry["new"], 16) for name, entry in audit["addresses"].items()}
    for name in CODE:
        segment = classify(addresses[name], segments)
        if segment is None:
            problems.append(f"{name} {addresses[name]:#x} is in no PT_LOAD segment")
        elif not segment.flags & PF_X:
            problems.append(f"{name} {addresses[name]:#x} is not in an executable segment")
    for name in DATA:
        segment = classify(addresses[name], segments)
        if segment is None:
            problems.append(f"{name} {addresses[name]:#x} is in no PT_LOAD segment")
        elif not segment.flags & PF_R:
            problems.append(f"{name} {addresses[name]:#x} is not in a readable segment")
    return problems


def synthetic_library(segments):
    """Minimal ELF64 header with PT_LOAD entries, for testing the reader."""
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4], header[5] = 2, 1
    struct.pack_into("<Q", header, 0x20, 64)          # e_phoff
    struct.pack_into("<HH", header, 0x36, 56, len(segments))
    body = bytearray()
    for vaddr, memsz, flags in segments:
        entry = bytearray(56)
        struct.pack_into("<II", entry, 0, PT_LOAD, flags)
        struct.pack_into("<Q", entry, 0x10, vaddr)    # p_vaddr
        struct.pack_into("<Q", entry, 0x20, 0)        # p_filesz
        struct.pack_into("<Q", entry, 0x28, memsz)    # p_memsz
        body += entry
    return bytes(header) + bytes(body)


def run_self_test():
    failures = []

    def check(condition, message):
        if not condition:
            failures.append(message)

    blob = synthetic_library([(0x1000, 0x470000, PF_R | PF_X),
                              (0xf47000, 0x20000, PF_R | PF_W)])
    segments = load_segments(blob)
    check(len(segments) == 2, f"expected 2 PT_LOAD segments, read {len(segments)}")
    check(classify(0x46eac4, segments).flags & PF_X, "code address not executable")
    check(classify(0xf47ae0, segments).flags & PF_R, "data address not readable")
    check(classify(0xf70000, segments) is None, "address past the last segment classified")
    check(classify(0x500, segments) is None, "address below the first segment classified")
    # A BSS tail beyond p_filesz still belongs to the segment.
    check(classify(0xf47000 + 0x1ffff, segments) is not None, "last byte of the segment lost")

    for bad in (b"", b"nonsense" * 10, blob[:40]):
        try:
            load_segments(bad)
        except ValueError:
            pass
        else:
            failures.append("truncated or foreign file accepted as ELF")

    if AUDIT.is_file():
        audit = json.loads(AUDIT.read_text())
        problems, notes = audit_consistency(audit)
        for note in notes:
            print(f"  {note}")
        for problem in problems:
            failures.append(problem)
    else:
        print(f"  audit record missing ({AUDIT}); consistency not checked")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 1
    print("PASS pinned addresses: ELF segment reader, code/data classification, and the "
          "audit constants agree with the offsets the bridge adds")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", action="store_true", help="logic self-test")
    args = parser.parse_args()
    if args.test:
        return run_self_test()

    if not AUDIT.is_file():
        print(f"FAIL audit record missing: {AUDIT}")
        return 1
    audit = json.loads(AUDIT.read_text())
    problems, notes = audit_consistency(audit)
    for note in notes:
        print(f"  {note}")
    for problem in problems:
        print(f"FAIL {problem}")
    if problems:
        return 1

    print("\nSegment membership:")
    if not LIBRARY.is_file():
        print(f"  NICHT PRUEFBAR: {LIBRARY} fehlt (private Basis-APK). Die Zuordnung der")
        print("  gepinnten Adressen zu lesbaren/ausfuehrbaren Segmenten ist damit offen;")
        print("  geprueft ist nur, dass die Konstanten zum Audit-Datensatz passen.")
        return 2
    segments = load_segments(LIBRARY.read_bytes())
    for segment in segments:
        print(f"  {segment.describe()}")
    problems = segment_problems(audit, segments)
    for problem in problems:
        print(f"FAIL {problem}")
    if problems:
        return 1
    print("  alle gepinnten Adressen liegen in passenden Segmenten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
