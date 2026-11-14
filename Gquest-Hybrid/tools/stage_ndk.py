#!/usr/bin/env python3
"""Stage a minimal NDK so the bridge can be cross-compiled without a full SDK.

`build.py --tests` compiles `bridge/quest_engine_bridge.cpp` for
aarch64-linux-android29 to type-check its JNI calls. That needs clang and the Android
sysroot headers, but not the full NDK: linking `liblauncheq.so` against the base APK is
a different step that also needs the private APK.

This script fetches the pinned NDK release and extracts only what the check uses
(~140 MB staged instead of a 1.5 GB SDK install). Everything lands in
`work/toolchains/android-ndk/`, which `.gitignore` excludes.

Usage:
    python3 Gquest-Hybrid/tools/stage_ndk.py            # download + stage
    python3 Gquest-Hybrid/tools/stage_ndk.py --zip F    # use an existing NDK zip
    python3 Gquest-Hybrid/tools/stage_ndk.py --check    # only report what is staged
"""
import argparse
import os
import re
import stat
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
TARGET = BASE / "work/toolchains/android-ndk"
URL = "https://dl.google.com/android/repository/android-ndk-r23c-linux.zip"
PREFIX = "android-ndk-r23c/toolchains/llvm/prebuilt/linux-x86_64/"
CLANG = PREFIX + "bin/clang-12"
SYSROOT = PREFIX + "sysroot/usr/include/"
RESOURCE = PREFIX + "lib64/clang/12.0.9/include/"
# Candidate names are matched exactly, everything else under these trees is skipped.
LIB = re.compile(re.escape(PREFIX) + r"lib64/[^/]+\.so(\.\d+)*$")


def staged() -> bool:
    return (TARGET / "bin/clang-12").exists() and (TARGET / "sysroot/usr/include").is_dir()


def wanted(name: str) -> bool:
    """Only regular files we actually use; symlinks are skipped on purpose."""
    if name.endswith("/"):
        return False  # directory entry, created implicitly by the files inside it
    if name == CLANG:
        return True
    if name.startswith(SYSROOT) or name.startswith(RESOURCE):
        return True
    return bool(LIB.match(name))


def extract(archive: Path) -> int:
    written = 0
    with zipfile.ZipFile(archive) as bundle:
        for info in bundle.infolist():
            if info.is_dir() or not wanted(info.filename):
                continue
            # Symlinks are stored as links with tiny payloads; we call clang-12 directly,
            # so they are not needed and would only be written as broken text files.
            if stat.S_ISLNK(info.external_attr >> 16):
                continue
            relative = info.filename[len(PREFIX):]
            destination = TARGET / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(info) as source:
                destination.write_bytes(source.read())
            # zipfile does not restore permissions: without this clang-12 lands as a
            # non-executable file and every later run fails with PermissionError.
            mode = (info.external_attr >> 16) & 0o777
            if mode:
                destination.chmod(mode)
            written += 1
    return written


def report() -> bool:
    if not staged():
        print(f"nicht bereit: {TARGET} enthaelt kein clang-12/sysroot")
        return False
    size = sum(f.stat().st_size for f in TARGET.rglob("*") if f.is_file())
    print(f"bereit: {TARGET} ({size / 1e6:.0f} MB)")
    clang = TARGET / "bin/clang-12"
    if not os.access(clang, os.X_OK):
        print(f"clang-12 ist nicht ausfuehrbar: chmod +x {clang}")
        return False
    try:
        probe = subprocess.run([str(clang), "--version"], capture_output=True, text=True,
                               env=dict(os.environ, LD_LIBRARY_PATH=str(TARGET / "lib64")))
    except OSError as error:
        print(f"clang-12 laesst sich nicht starten: {error}")
        return False
    output = probe.stdout or probe.stderr
    print(output.splitlines()[0] if output else "")
    return probe.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", type=Path, default=None, help="bereits geladene NDK-Zip")
    parser.add_argument("--check", action="store_true", help="nur den Stand melden")
    arguments = parser.parse_args()
    if arguments.check:
        return 0 if report() else 1
    if staged():
        print("bereits vorhanden, nichts zu tun")
        report()
        return 0
    archive = arguments.zip
    if archive is None:
        archive = Path("/tmp") / Path(URL).name
        if not archive.exists():
            print(f"lade {URL} ({Path(URL).name}) nach {archive} ...")
            urllib.request.urlretrieve(URL, archive)
    if not archive.exists():
        print(f"Zip nicht gefunden: {archive}")
        return 1
    print(f"entpacke Auswahl aus {archive} ...")
    written = extract(archive)
    print(f"{written} Dateien nach {TARGET}")
    return 0 if report() else 1


if __name__ == "__main__":
    sys.exit(main())
