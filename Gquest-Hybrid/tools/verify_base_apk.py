#!/usr/bin/env python3
"""Check a supplied GDroid base APK against every pin before anything is built.

The build's own step 1 (``work/verify_gdroid_base.py``) asserts: the first mismatch raises and
the rest is never looked at. That is right for a build and wrong for a download, where the
useful answer is "these four things differ and here is what was expected".

So this script collects findings and reports all of them:

    python3 Gquest-Hybrid/tools/verify_base_apk.py                 # outputs/GDroid-0.1.30.apk
    python3 Gquest-Hybrid/tools/verify_base_apk.py path/to/base.apk
    python3 Gquest-Hybrid/tools/verify_base_apk.py --test          # self-test, synthetic APKs

Exit status: 0 everything matches, 1 at least one check failed, 2 no APK at the given path.
A certain-looking 0 is worth nothing unless the checker itself is known to fail on bad input,
which is what ``--test`` establishes: it builds APKs that differ in exactly one place and
requires the matching finding.
"""
from __future__ import annotations

import hashlib
import json
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BASE = PROJECT.parent
DEFAULT_APK = BASE / "outputs/GDroid-0.1.30.apk"
PIN = BASE / "work/gdroid-0.1.30-build-pin.json"
AUDIT = BASE / "work/gdroid130-compat/audit.json"
NATIVE_DIR = BASE / "work/gdroid-0.1.30-native"
ABI_PREFIX = "lib/arm64-v8a/"

# The four functions the audit pins by exact machine code, and their key in the pin's
# signature table. Reading them from a different APK than the audited one is pointless, so
# every name has to resolve.
SIGNATURES = {
    "pose_constructor": "constructor",
    "finger_blend_function": "blend",
    "layer_allocator": "allocator",
    "local_hand_pose": "localpose",
}

OK, WARN, BAD = "ok", "warn", "bad"


class Report:
    def __init__(self):
        self.findings: list[tuple[str, str, str]] = []

    def add(self, state: str, subject: str, detail: str = ""):
        self.findings.append((state, subject, detail))

    @property
    def failed(self) -> bool:
        return any(state == BAD for state, _, _ in self.findings)

    def print(self):
        symbols = {OK: "[ok]  ", WARN: "[hinweis]", BAD: "[FEHLER]"}
        for state, subject, detail in self.findings:
            line = f"  {symbols[state]} {subject}"
            if detail:
                line += f"\n           {detail}"
            print(line, flush=True)


def elf_reader(image: bytes):
    """Return read(va, size) for an ELF64 image, or None when it is not one.

    Only PT_LOAD segments are mapped; a virtual address outside all of them is a genuine
    failure to read, never a silently different offset.
    """
    if len(image) < 64 or image[:4] != b"\x7fELF" or image[4] != 2:
        return None
    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", image, 54)
    if phentsize < 56 or phoff + phentsize * phnum > len(image):
        return None
    segments = [struct.unpack_from("<IIQQQQQQ", image, phoff + i * phentsize)
                for i in range(phnum)]
    loads = [s for s in segments if s[0] == 1]

    def read(va: int, size: int):
        for _, _, offset, vaddr, _, filesz, _, _ in loads:
            if vaddr <= va and va + size <= vaddr + filesz:
                start = offset + va - vaddr
                return image[start:start + size]
        return None

    return read


def check_native_entries(zf: zipfile.ZipFile, pin: dict, report: Report) -> None:
    names = sorted(pin["native_sha256"])
    present = set(zf.namelist())
    missing = [n for n in names if ABI_PREFIX + n not in present]
    if missing:
        report.add(BAD, f"{len(missing)} of {len(names)} pinned native libraries are missing",
                   ", ".join(missing))
    mismatched = []
    for name in names:
        entry = ABI_PREFIX + name
        if entry not in present:
            continue
        digest = hashlib.sha256(zf.read(entry)).hexdigest()
        if digest != pin["native_sha256"][name]:
            mismatched.append(f"{name}: erwartet {pin['native_sha256'][name][:16]}…, "
                              f"gefunden {digest[:16]}…")
    if mismatched:
        report.add(BAD, f"{len(mismatched)} native libraries differ from the pin",
                   "; ".join(mismatched))
    if not missing and not mismatched:
        report.add(OK, f"all {len(names)} pinned native libraries match their digests")


def check_patch(client: bytes, pin: dict, report: Report) -> bool:
    """Require the VR-init patch site to hold exactly the audited bytes."""
    patch = pin["client_vr_player_patch"]
    offset = int(patch["file_offset"], 0)
    window = client[offset:offset + 4]
    if len(window) != 4:
        report.add(BAD, "libclient.so is shorter than the pinned patch offset",
                   f"offset {patch['file_offset']} lies outside the file")
        return False
    found = window.hex()
    if found != patch["before"]:
        report.add(BAD, "VR-init patch site does not hold the audited bytes",
                   f"at {patch['file_offset']} (VA {patch['va']}) expected {patch['before']}, "
                   f"found {found} - a different build, or already patched")
        return False
    report.add(OK, f"VR-init patch site holds {patch['before']} at {patch['file_offset']}")
    return True


def check_signatures(client: bytes, audit: dict, report: Report) -> None:
    read = elf_reader(client)
    if read is None:
        report.add(BAD, "libclient.so is not a readable ELF64 image",
                   "the pinned addresses cannot be checked against anything")
        return
    passed = 0
    for target, key in SIGNATURES.items():
        expected = audit["exact_signature_checks"][key]
        address = int(audit["addresses"][target]["new"], 0)
        data = read(address, expected["size"])
        if data is None:
            report.add(BAD, f"{key}: address {hex(address)} is in no loaded segment",
                       "the pin and the file do not belong together")
            continue
        if data.hex() != expected["hex"]:
            report.add(BAD, f"{key}: machine code differs from the audit",
                       f"at {hex(address)} expected {expected['hex'][:24]}…, "
                       f"found {data.hex()[:24]}…")
            continue
        passed += 1
    if passed == len(SIGNATURES):
        report.add(OK, f"all {len(SIGNATURES)} pinned function signatures match")

    call = int(audit["addresses"]["finger_blend_call"]["new"], 0)
    target = int(audit["addresses"]["finger_blend_function"]["new"], 0)
    word = read(call, 4)
    if word is None:
        report.add(BAD, f"blend call site {hex(call)} is in no loaded segment")
        return
    instruction = struct.unpack("<I", word)[0]
    if instruction >> 26 != 0b100101:
        report.add(BAD, "blend call site is not a branch-with-link",
                   f"opcode {instruction >> 26:06b} at {hex(call)}")
        return
    delta = instruction & 0x3FFFFFF
    if delta & (1 << 25):
        delta -= 1 << 26
    landed = call + delta * 4
    if landed != target:
        report.add(BAD, "blend call does not branch to the pinned blend function",
                   f"from {hex(call)} it lands on {hex(landed)}, pinned target {hex(target)}")
    else:
        report.add(OK, f"blend call at {hex(call)} branches to {hex(target)}")


def check_apk(apk: Path, pin: dict, audit: dict) -> Report:
    report = Report()
    if not apk.is_file():
        report.add(BAD, "no base APK at the given path",
                   f"{apk} does not exist - nothing can be patched or repackaged")
        return report

    data = apk.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != pin["apk_sha256"]:
        report.add(BAD, f"APK digest is not the pinned {pin['version']}",
                   f"expected {pin['apk_sha256']}\n           found    {digest}\n"
                   f"           The patch offsets and signatures below only hold for the "
                   f"pinned build.")
    else:
        report.add(OK, f"APK digest matches the pinned {pin['version']}")

    try:
        zf = zipfile.ZipFile(apk)
    except zipfile.BadZipFile as error:
        report.add(BAD, "file is not a readable APK/ZIP", str(error))
        return report

    with zf:
        if zf.testzip() is not None:
            report.add(BAD, "archive is corrupt", f"first bad member: {zf.testzip()}")
        else:
            report.add(OK, f"archive integrity is fine, {len(zf.namelist())} members")
        if ABI_PREFIX + "libclient.so" not in zf.namelist():
            report.add(BAD, "no lib/arm64-v8a/libclient.so",
                       "this is either not a GDroid APK or not the arm64 build")
            return report
        check_native_entries(zf, pin, report)
        client = zf.read(ABI_PREFIX + "libclient.so")
        if check_patch(client, pin, report):
            check_signatures(client, audit, report)

    # Informational: the build links against the extracted copies, so a folder that does not
    # match the APK yields a package whose native code was never the tested one.
    if NATIVE_DIR.is_dir():
        differing = []
        for name in sorted(pin["native_sha256"]):
            path = NATIVE_DIR / name
            if not path.is_file():
                differing.append(f"{name}: missing")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != pin["native_sha256"][name]:
                differing.append(f"{name}: different digest")
        if differing:
            report.add(WARN, "work/gdroid-0.1.30-native/ disagrees with the APK",
                       "; ".join(differing[:6]) + (" …" if len(differing) > 6 else ""))
        else:
            report.add(OK, "work/gdroid-0.1.30-native/ matches the APK")
    else:
        report.add(WARN, "work/gdroid-0.1.30-native/ does not exist yet",
                   "build.py expects the 34 libraries there; create it with "
                   "unzip -o -j <apk> 'lib/arm64-v8a/*.so' -d work/gdroid-0.1.30-native")
    return report


# --- self-test -------------------------------------------------------------------------

CODE_VA = 0x100000
CODE_OFFSET = 0x1000
CONSTRUCTOR = "ff8304d1eb2b0a6de9230b6dfd7b0ca9fc6f0da9fa670ea9f85f0fa9f65710a9"
BLEND = "ff8303d1e84b00fdfdfb09a9"
ALLOCATOR = "ff0302d1fd7b02a9fc6f03a9fa6704a9f85f05a9f65706a9f44f07a9fd830091"
LOCALPOSE = "ff0302d1fd7b06a9f33b00f9fd830191f30308aa08f0a752ffc302f8e82300b9"
ADDRESSES = {"pose_constructor": 0x100100, "finger_blend_function": 0x100200,
             "layer_allocator": 0x100300, "local_hand_pose": 0x100400,
             "finger_blend_call": 0x100500}
PATCH_VA = 0x100600
PATCH_BEFORE = "e1031f2a"
PATCH_AFTER = "21008052"
NATIVE = {"libGameUI.so": b"gameui-fixture", "libclient.so": b""}


def file_offset(va: int) -> int:
    return CODE_OFFSET + (va - CODE_VA)


def build_client(blend_target: int = ADDRESSES["finger_blend_function"],
                 blend_bytes: str = BLEND, patch: str = PATCH_BEFORE) -> bytes:
    """A minimal ELF64 with one PT_LOAD segment holding the pinned bytes at the pinned VAs."""
    size = file_offset(0x100700)
    image = bytearray(size)
    image[0:4] = b"\x7fELF"
    image[4] = 2                     # 64-bit
    image[5] = 1                     # little endian
    image[6] = 1                     # current version
    struct.pack_into("<HHI", image, 16, 2, 0xB7, 1)      # e_type ET_EXEC, e_machine AARCH64
    struct.pack_into("<Q", image, 24, CODE_VA)            # e_entry
    struct.pack_into("<Q", image, 32, 64)                 # e_phoff
    struct.pack_into("<HH", image, 54, 56, 1)             # e_phentsize, e_phnum
    struct.pack_into("<IIQQQQQQ", image, 64, 1, 5, CODE_OFFSET, CODE_VA, CODE_VA,
                     size - CODE_OFFSET, size - CODE_OFFSET, 0x1000)
    for va, hexbytes in ((ADDRESSES["pose_constructor"], CONSTRUCTOR),
                         (ADDRESSES["finger_blend_function"], blend_bytes),
                         (ADDRESSES["layer_allocator"], ALLOCATOR),
                         (ADDRESSES["local_hand_pose"], LOCALPOSE),
                         (PATCH_VA, patch)):
        offset = file_offset(va)
        image[offset:offset + len(hexbytes) // 2] = bytes.fromhex(hexbytes)
    delta = (blend_target - ADDRESSES["finger_blend_call"]) // 4
    instruction = 0x94000000 | (delta & 0x3FFFFFF)
    struct.pack_into("<I", image, file_offset(ADDRESSES["finger_blend_call"]), instruction)
    return bytes(image)


def write_apk(path: Path, client: bytes, natives: dict | None = None) -> None:
    entries = dict(NATIVE if natives is None else natives)
    entries["libclient.so"] = client
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, payload in entries.items():
            zf.writestr(ABI_PREFIX + name, payload)


def selftest() -> int:
    audit = {"addresses": {k: {"new": hex(v)} for k, v in ADDRESSES.items()},
             "exact_signature_checks": {
                 "constructor": {"size": 32, "hex": CONSTRUCTOR},
                 "blend": {"size": 12, "hex": BLEND},
                 "allocator": {"size": 32, "hex": ALLOCATOR},
                 "localpose": {"size": 32, "hex": LOCALPOSE}}}

    def pin_for(client: bytes) -> dict:
        natives = {"libGameUI.so": hashlib.sha256(NATIVE["libGameUI.so"]).hexdigest()}
        return {"version": "fixture", "apk_sha256": "",
                "client_vr_player_patch": {"file_offset": hex(file_offset(PATCH_VA)),
                                           "va": hex(PATCH_VA), "before": PATCH_BEFORE,
                                           "after": PATCH_AFTER},
                "native_sha256": natives}

    def run(path: Path, client: bytes) -> Report:
        report = check_apk(path, pin_for(client), audit)
        return report

    # The digest check is skipped for fixtures by construction: the pin's digest is filled in
    # from the file itself, so only the structural checks are under test here.
    def with_digest(path: Path, base_pin: dict) -> dict:
        return {**base_pin, "apk_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)

        cases = []

        def case(name: str, client: bytes, expect_ok: bool, expect: str,
                 apk_natives: dict | None = None, pin_natives: dict | None = None):
            """One fixture APK. `pin_natives` is what the pin expects and defaults to the
            intact libraries; passing the APK's own digests back in would make a tampering
            case compare the file against itself and always agree."""
            path = tmp / (name.replace(" ", "_") + ".apk")
            write_apk(path, client, apk_natives)
            expected = NATIVE if pin_natives is None else pin_natives
            natives_pin = {n: hashlib.sha256(p).hexdigest() for n, p in expected.items()
                           if n != "libclient.so"}
            pin = {**pin_for(client), "native_sha256": natives_pin}
            pin = with_digest(path, pin)
            report = check_apk(path, pin, audit)
            states = [s for s, _, _ in report.findings]
            got_ok = not report.failed
            if got_ok != expect_ok:
                failures.append(f"{name}: expected {'pass' if expect_ok else 'fail'}, "
                                f"got {'pass' if got_ok else 'fail'}\n"
                                + "\n".join(f"  {s} {subj} {det}" for s, subj, det in
                                            report.findings))
            elif expect and not any(expect in f"{subj} {det}"
                                    for _, subj, det in report.findings):
                failures.append(f"{name}: no finding mentions {expect!r}")
            cases.append((name, got_ok, states))

        case("intact fixture", build_client(), True, "")
        broken = bytearray(build_client())
        broken[file_offset(ADDRESSES["finger_blend_function"])] ^= 0xFF
        case("blend signature altered", bytes(broken), False, "blend")
        case("patch site already patched", build_client(patch=PATCH_AFTER), False, "VR-init")
        case("blend call points elsewhere",
             build_client(blend_target=ADDRESSES["layer_allocator"]), False, "branch")
        case("native library altered", build_client(), False, "libGameUI.so",
             {"libGameUI.so": b"gameui-fixture-tampered", "libclient.so": b""})
        case("native library missing", build_client(), False, "missing",
             {"libclient.so": b""})

        not_zip = tmp / "not-an-apk.apk"
        not_zip.write_bytes(b"this is not a zip archive")
        report = check_apk(not_zip, pin_for(b""), audit)
        if not report.failed:
            failures.append("not-a-zip: expected a failure")
        elif not any("readable" in f"{s} {d}" for _, s, d in report.findings):
            failures.append("not-a-zip: no finding mentions a readable archive")

        absent = check_apk(tmp / "does-not-exist.apk", pin_for(b""), audit)
        if not absent.failed or "does not exist" not in " ".join(
                f"{s} {d}" for _, s, d in absent.findings):
            failures.append("missing file: expected a 'does not exist' failure")

    if failures:
        print("FAIL base APK checker self-test:")
        for line in failures:
            print("  " + line)
        return 1
    print("PASS base APK checker: an intact fixture passes; an altered signature, an already "
          "patched site, a blend call pointing elsewhere, a tampered and a missing native "
          "library, a non-archive and an absent file each fail with the matching finding")
    return 0


def main(argv: list[str]) -> int:
    if "--test" in argv[1:]:
        return selftest()
    target = next((Path(a) for a in argv[1:] if not a.startswith("-")), DEFAULT_APK).resolve()
    pin = json.loads(PIN.read_text())
    audit = json.loads(AUDIT.read_text())
    print(f"Base APK: {target}")
    print(f"Pinned:   GDroid {pin['version']}, sha256 {pin['apk_sha256']}")
    report = check_apk(target, pin, audit)
    print()
    report.print()
    missing_file = not target.is_file()
    print()
    if missing_file:
        print("Ergebnis: keine Datei zu prüfen (Exit 2).")
        return 2
    if report.failed:
        print("Ergebnis: Basis-APK passt NICHT zu den Pins (Exit 1). Der volle Build würde "
              "hier abbrechen.")
        return 1
    print("Ergebnis: Basis-APK passt zu allen Pins (Exit 0). Nächster Schritt: native "
          "Bibliotheken nach work/gdroid-0.1.30-native entpacken, dann bauen.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
