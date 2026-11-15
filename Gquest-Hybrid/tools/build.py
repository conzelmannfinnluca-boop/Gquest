"""Build the Rust/C++ bridge, package existing GDroid, check unchanged payloads.

Usage:
    python3 Gquest-Hybrid/tools/build.py --check   # prerequisites only, no build
    python3 Gquest-Hybrid/tools/build.py --tests   # tests that need no private data
    python3 Gquest-Hybrid/tools/build.py           # full build (needs everything)

The full build requires private files that are deliberately not in this repository
(pinned GDroid APK, native libraries, Android SDK/NDK, JDK, signing key, retail
content). ``--check`` reports every missing item with purpose and origin instead of
failing with a traceback.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import shutil
import subprocess
import os
import sys
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BASE = PROJECT.parent
WORK = BASE / "work"
OUT = PROJECT / "dist"

# Minimal staged NDK (clang + sysroot headers) from tools/stage_ndk.py. Enough to
# cross-compile the bridge, not to link it against the base APK.
STAGED_NDK = WORK / "toolchains/android-ndk"

NDK = WORK / "android-sdk/ndk/23.2.8568313/toolchains/llvm/prebuilt/linux-x86_64/bin"
TOOLS = WORK / "android-sdk/build-tools/34.0.0"
JAVA = WORK / "toolchains/jdk/bin/java"
CARGO = WORK / "toolchains/cargo/bin/cargo"
KEYSTORE = Path.home() / ".android/debug.keystore"

BASE_APK = BASE / "outputs/GDroid-0.1.30.apk"
BASE_APK_SHA256 = "28bcce6d656f324b883fa638ceae2893cfa875e423f28a7fbc2329c5cdd5d13c"

# Everything the full build touches but that must never be committed.
# (path, purpose, how to obtain)
PREREQUISITES: list[tuple[Path, str, str]] = [
    (BASE_APK, "Pinned official GDroid 0.1.30 base APK (SHA256 " + BASE_APK_SHA256[:12] + "…)",
     "Download release 0.1.30 from github.com/tinsarfal/GDroid. Cannot be built from "
     "source: upstream publishes binaries only."),
    (WORK / "gdroid-0.1.30-native", "Native libraries of that exact APK, unpacked",
     "Extract lib/arm64-v8a/*.so from the pinned APK into this folder."),
    (NDK, "Android NDK 23.2.8568313, needed to link liblauncheq.so (the cross-compile "
          "check also runs with the staged clang)",
     "sdkmanager --install 'ndk;23.2.8568313', target <repo>/work/android-sdk"),
    (TOOLS, "Android build-tools 34.0.0 (zipalign, apksigner)",
     "sdkmanager --install 'build-tools;34.0.0', target <repo>/work/android-sdk"),
    (JAVA, "JDK for apksigner",
     "Install a JDK, then place/link it at <repo>/work/toolchains/jdk"),
    (CARGO, "Rust toolchain with the aarch64-linux-android target",
     "Install rustup, add target aarch64-linux-android, place it at "
     "<repo>/work/toolchains/cargo. A system cargo is used if this is missing."),
    (WORK / "quest-vr-content-manifest.json", "Manifest of the private VR content payload",
     "Private project data. Not redistributable; recreate from your own content tree."),
    (WORK / "quest-vr-content", "The private VR content payload itself",
     "Private project data. Not redistributable."),
    (KEYSTORE, "Debug signing key for the repackaged APK",
     "keytool -genkeypair -keystore ~/.android/debug.keystore -alias androiddebugkey "
     "-storepass android -keypass android -keyalg RSA -validity 10000"),
]

# These files exist twice: the packaging folder and the bridge include folder.
# They must stay byte-identical, otherwise the shipped APK differs from the tested
# sources. This is checked instead of merging the trees, so the existing layout and
# every path in build/verify scripts keep working.
BRIDGE_MIRRORS: list[str] = [
    "quest_engine_bridge.cpp",
    "gquest_content_install.h",
    "gquest_device_jni.h",
    "gquest_device_profile.h",
    "gquest_readable_memory.h",
    "gquest_native_finger_profiles.h",
    "gquest_playspace.h",
    "gquest_pose_snapshot.h",
    "gquest_native_fingers.h",
    "gquest_retired_content.h",
    "gquest_signature.h",
    "gquest_vr_lua.h",
]

# Boundary tests that only need a host C++ compiler and the headers.
HOST_CPP_TESTS = ["native_fingers", "vr_lua", "retired_content", "device_model",
                  "device_jni", "content_install", "fake_host", "platform", "playspace",
                  "pose_snapshot", "readable_memory",
                  "signature_scan"]

# Lua boundary harnesses. They need a Lua 5.4 shared library but no private data;
# run_lua_checks.py resolves a locally built one or a system install.
LUA_HARNESSES = [
    "work/harness/test_hl2_grip_cache.lua",
    "work/harness/test_hl2_native_models.lua",
    "work/harness/test_hl2_equipment.lua",
    "work/harness/test_hl2_weapon_catalog.lua",
    "work/harness/test_native_pose_class.lua",
    "work/test_reload_client.lua",
    "work/harness/test_hl2_reload_refill.lua",
    "work/harness/test_perf_hud.lua",
    "work/harness/test_vr_profiles.lua",
    "work/test_gquest_menu_navigation.lua",
    "work/harness/test_playspace.lua",
    "work/harness/test_hand_smoothing.lua",
]


def log(message: str) -> None:
    print(message, flush=True)


def run(*args, cwd: Path | None = None) -> None:
    # Commands that resolve relative paths themselves (the work/ scripts) need the repo root,
    # cargo needs the crate: Cargo.toml lives in Gquest-Hybrid/, not in its parent.
    command = [str(a) for a in args]
    log("+ " + " ".join(command))
    subprocess.run(command, cwd=cwd or BASE, check=True)


def cargo_binary() -> Path | None:
    """Prefer the private toolchain, fall back to a system rustup install."""
    if CARGO.is_file():
        return CARGO
    system = shutil.which("cargo")
    return Path(system) if system else None


def cargo(*args) -> None:
    binary = cargo_binary()
    if binary is None:
        raise SystemExit(
            "cargo not found. Place a Rust toolchain at work/toolchains/cargo or "
            "install rustup. Run build.py --check for the full prerequisite list."
        )
    run(binary, *args, cwd=PROJECT)


# A prerequisite whose path may be absent while the code still works, because the runner
# falls back to a system install. Resolved the same way the runner resolves it, so --check
# never reports missing something the build would find.
PREREQUISITE_FALLBACKS = {CARGO: lambda: cargo_binary() is not None}


def check_prerequisites() -> list[tuple[bool, Path, str, str]]:
    def present(path: Path) -> bool:
        fallback = PREREQUISITE_FALLBACKS.get(path)
        return path.exists() or bool(fallback and fallback())

    return [(present(path), path, purpose, obtain)
            for path, purpose, obtain in PREREQUISITES]


def lua_library() -> str | None:
    """Resolve Lua 5.4 by loading it, exactly like work/run_lua_checks.py does."""
    for candidate in (os.environ.get("GQUEST_LUA_LIB"),
                      str(WORK / "toolchains/lua/lib/liblua5.4.so.0"),
                      "liblua5.4.so.0", "liblua5.4.so"):
        if not candidate:
            continue
        try:
            ctypes.CDLL(candidate)
        except OSError:
            continue
        return candidate
    return None


def check_test_prerequisites() -> list[tuple[bool, str, str, str]]:
    """What the test groups need: (present, label, purpose, how to obtain).

    Resolved the way the runners resolve it, so this never disagrees with the run that
    follows. A missing entry does not stop the build; that group then reports
    UEBERSPRUNGEN and is absent from the coverage.
    """
    return [
        (shutil.which("c++") is not None, "Host-C++-Compiler (c++)",
         f"{len(HOST_CPP_TESTS)} C++-Grenztests und C++/Rust-ABI-Smoke",
         "g++ oder clang++ installieren (build-essential); ein Host-Compiler genuegt"),
        (cargo_binary() is not None, "cargo",
         "Rust-Unit-Tests und C++/Rust-ABI-Smoke",
         "rustup installieren oder eine Toolchain unter work/toolchains/cargo ablegen"),
        (bridge_compiler() is not None, "Cross-Compiler fuer die Bridge",
         "Bridge-Cross-Compile (aarch64-linux-android29, -Werror)",
         "vollen NDK installieren oder: python3 Gquest-Hybrid/tools/stage_ndk.py"),
        (lua_library() is not None, "Lua-5.4-Bibliothek",
         f"{len(LUA_HARNESSES)} Lua-Harnesses",
         "liblua5.4 installieren, GQUEST_LUA_LIB setzen oder work/toolchains/lua bauen"),
    ]


def check_mirrors() -> list[str]:
    """Return a list of human-readable problems with the duplicated bridge files."""
    problems = []
    mirror_root = WORK
    source_root = PROJECT / "bridge"
    for name in BRIDGE_MIRRORS:
        packaged = mirror_root / name
        compiled = source_root / name
        if not packaged.is_file() or not compiled.is_file():
            missing = packaged if not packaged.is_file() else compiled
            problems.append(f"{name}: missing at {missing}")
            continue
        if packaged.read_bytes() != compiled.read_bytes():
            problems.append(
                f"{name}: work/ and Gquest-Hybrid/bridge/ differ — the shipped copy "
                f"is not the tested copy"
            )
    return problems


def report_check() -> int:
    results = check_prerequisites()
    missing = [r for r in results if not r[0]]

    log(f"GQuest build prerequisites ({len(results) - len(missing)}/{len(results)} present)\n")
    for present, path, purpose, obtain in results:
        log(f"  [{'ok' if present else 'MISSING'}] {path}")
        log(f"     Zweck:  {purpose}")
        if not present:
            log(f"     Quelle: {obtain}")
        log("")

    mirror_problems = check_mirrors()
    log("Bridge-Spiegel (work/ == Gquest-Hybrid/bridge/):")
    log("  [ok] alle Dateien byte-identisch" if not mirror_problems else "")
    for problem in mirror_problems:
        log(f"  [FAIL] {problem}")

    test_results = check_test_prerequisites()
    test_missing = [r for r in test_results if not r[0]]
    log(f"\nTest-Voraussetzungen ({len(test_results) - len(test_missing)}"
        f"/{len(test_results)} vorhanden):")
    log("  Fehlt eine, laeuft die betroffene Gruppe nicht und erscheint als "
        "UEBERSPRUNGEN; der Build bleibt moeglich.")
    for present, label, purpose, obtain in test_results:
        log(f"  [{'ok' if present else 'MISSING'}] {label}: {purpose}")
        if not present:
            log(f"     Quelle: {obtain}")

    if missing:
        log(f"\n{len(missing)} Voraussetzung(en) fehlen. Der volle Build ist damit nicht möglich.")
        log("Ohne private Daten pruefbar: python3 Gquest-Hybrid/tools/build.py --units")
        return 1
    if mirror_problems:
        log("\nVoraussetzungen vollständig, aber die Spiegelprüfung ist fehlgeschlagen.")
        return 1
    log("\nAlle Voraussetzungen vorhanden. Voller Build möglich.")
    return 0


def run_rust_tests() -> str:
    """Run the Rust unit tests. Returns 'passed', 'skipped' or 'failed'."""
    log("\n=== Rust-Unit-Tests ===")
    if cargo_binary() is None:
        log("SKIPPED: kein cargo gefunden (work/toolchains/cargo oder PATH)")
        log("  rustup installieren, dann laufen diese Tests mit.")
        return "skipped"
    command = [sys.executable, str(PROJECT / "tools/cargo.py"), "test", "--offline"]
    log("+ " + " ".join(command))
    result = subprocess.run(command, cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    interesting = [line for line in output.splitlines()
                   if line.startswith("test result:") or line.endswith(" ok")
                   or "FAILED" in line or "panicked" in line]
    log("\n".join(interesting[-9:]) or output.splitlines()[-1] if output else "keine Ausgabe")
    return "passed" if result.returncode == 0 else "failed"


def run_abi_smoke() -> str:
    """Build the Rust release library and run the C++/Rust ABI boundary test."""
    log("\n=== C++/Rust-ABI-Smoke ===")
    if cargo_binary() is None:
        log("SKIPPED: braucht den Rust-Release-Build")
        return "skipped"
    build = subprocess.run(
        [sys.executable, str(PROJECT / "tools/cargo.py"), "build", "--release", "--offline"],
        cwd=BASE, capture_output=True, text=True)
    if build.returncode != 0:
        log("FAILED: cargo build --release")
        log((build.stdout + build.stderr).strip()[-1500:])
        return "failed"
    OUT.mkdir(exist_ok=True)
    library = PROJECT / "target/release/libgquest_runtime.a"
    binary = OUT / "ffi-smoke"
    command = ["c++", "-std=c++17", f"-I{PROJECT / 'include'}",
               str(PROJECT / "tests/ffi_smoke.cpp"), str(library),
               "-ldl", "-lpthread", "-lm", "-o", str(binary)]
    log("+ " + " ".join(command))
    compiled = subprocess.run(command, cwd=BASE, capture_output=True, text=True)
    if compiled.returncode != 0:
        log("BUILD FAILED")
        log(compiled.stderr.strip()[-1500:])
        return "failed"
    executed = subprocess.run([str(binary)], cwd=BASE, capture_output=True, text=True)
    if executed.stdout.strip():
        log(executed.stdout.strip())
    if executed.returncode != 0:
        log(f"FAILED (exit {executed.returncode})")
        if executed.stderr.strip():
            log(executed.stderr.strip()[-1500:])
        return "failed"
    return "passed"


def bridge_compiler():
    """Return (compiler argv, sysroot, env) for an aarch64 Android compile, or None."""
    full = NDK / "aarch64-linux-android29-clang++"
    if full.exists():
        sysroot = NDK.parent / "sysroot"
        return [str(full)], sysroot, None
    staged = STAGED_NDK / "bin/clang-12"
    if staged.exists() and (STAGED_NDK / "sysroot/usr/include").is_dir():
        env = dict(os.environ, LD_LIBRARY_PATH=str(STAGED_NDK / "lib64"))
        return [str(staged), "--driver-mode=g++"], STAGED_NDK / "sysroot", env
    return None


def run_bridge_compile() -> str:
    """Cross-compile the Android bridge so its JNI calls are type-checked.

    Returns 'passed', 'skipped' or 'failed'. This compiles only; linking liblauncheq.so
    still needs the private base APK and stays part of the full build.
    """
    log("\n=== Android-Bridge (aarch64-Cross-Compile) ===")
    found = bridge_compiler()
    if found is None:
        log("SKIPPED: kein NDK gefunden; der Bridge-Code ist damit NICHT typgeprueft.")
        log("  Vollstaendig: sdkmanager --install 'ndk;23.2.8568313' nach work/android-sdk")
        log("  Nur clang + Header: python3 Gquest-Hybrid/tools/stage_ndk.py")
        return "skipped"
    compiler, sysroot, env = found
    OUT.mkdir(exist_ok=True)
    object_file = OUT / "quest_engine_bridge.o"
    command = [*compiler, "--target=aarch64-linux-android29", f"--sysroot={sysroot}",
               "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-c",
               f"-I{PROJECT / 'bridge'}", f"-I{PROJECT / 'include'}",
               str(PROJECT / "bridge/quest_engine_bridge.cpp"), "-o", str(object_file)]
    log(f"  Toolchain: {compiler[0]}")
    log(f"+ {compiler[0]} --target=aarch64-linux-android29 -c bridge/quest_engine_bridge.cpp")
    compiled = subprocess.run(command, cwd=BASE, capture_output=True, text=True, env=env)
    if compiled.stdout.strip():
        log(compiled.stdout.strip()[-1500:])
    if compiled.returncode != 0:
        log("FAILED")
        log(compiled.stderr.strip()[-3000:])
        return "failed"
    if compiled.stderr.strip():
        log(compiled.stderr.strip()[-1500:])
    log("PASS bridge cross-compiles for aarch64-linux-android29 (keine Warnung, -Werror)")
    return "passed"


def run_perf_report_selftest() -> str:
    """Check the measurement evaluation against synthetic runs (no hardware needed)."""
    log("\n=== Performance-Auswertung (Selbsttest) ===")
    result = subprocess.run(
        [sys.executable, str(PROJECT / "tools/perf_report.py"), "--test"],
        cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if output:
        log(output[-1500:])
    return "passed" if result.returncode == 0 else "failed"


def run_capture_selftest() -> str:
    """Check the device capture tool with a stub adb (no headset needed)."""
    log("\n=== Geraeteerfassung (Selbsttest) ===")
    result = subprocess.run(
        [sys.executable, str(PROJECT / "tools/capture_device.py"), "--test"],
        cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if output:
        log("\n".join(line for line in output.splitlines()
                      if line.startswith(("PASS", "FAIL"))))
    return "passed" if result.returncode == 0 else "failed"


def run_manifest_selftest() -> str:
    """Check the supportedDevices reader/merger on synthetic manifests."""
    log("\n=== Ueberlagerungs-Manifest (Selbsttest) ===")
    result = subprocess.run(
        [sys.executable, str(PROJECT / "tools/overlay_manifest.py"), "--test"],
        cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if output:
        log("\n".join(line for line in output.splitlines()
                      if line.startswith(("PASS", "FAIL"))))
    return "passed" if result.returncode == 0 else "failed"


def run_pinned_selftest() -> str:
    """Check the pinned address constants against the audit record."""
    log("\n=== Gepinnte Adressen (Selbsttest) ===")
    result = subprocess.run(
        [sys.executable, str(PROJECT / "tools/pinned_addresses.py"), "--test"],
        cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if output:
        log("\n".join(output.splitlines()[-6:]))
    return "passed" if result.returncode == 0 else "failed"


def run_frame_policy_selftest() -> str:
    """Check that no weapon or hand path integrates raw frame time."""
    log("\n=== Frame-Zeit-Politik (Selbsttest) ===")
    result = subprocess.run(
        [sys.executable, str(PROJECT / "tools/frame_policy.py"), "--test"],
        cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if output:
        log("\n".join(output.splitlines()[-6:]))
    return "passed" if result.returncode == 0 else "failed"


def run_base_apk_selftest() -> str:
    """Check the preflight checker against fixtures that differ in exactly one place."""
    log("\n=== Basis-APK-Pruefung (Selbsttest) ===")
    result = subprocess.run(
        [sys.executable, str(PROJECT / "tools/verify_base_apk.py"), "--test"],
        cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if output:
        log("\n".join(output.splitlines()[-6:]))
    return "passed" if result.returncode == 0 else "failed"


def run_lua_harnesses() -> str:
    """Run the Lua harnesses. Returns 'passed', 'skipped' or 'failed'."""
    log("\n=== Lua-Harnesses ===")
    command = [sys.executable, str(WORK / "run_lua_checks.py"), *LUA_HARNESSES]
    log("+ " + " ".join(command))
    result = subprocess.run(command, cwd=BASE, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if result.returncode == 2:
        log("SKIPPED: " + output.splitlines()[0])
        log("  liblua5.4 fehlt. Lokal bauen: siehe BUILD.md, Abschnitt 'Lua-Harnesses'.")
        return "skipped"
    tail = "\n".join(output.splitlines()[-9:])
    log(tail)
    return "passed" if result.returncode == 0 else "failed"


def run_cpp_boundary_tests() -> list[str]:
    """Compile and run the host boundary tests; returns the names that did not pass."""
    OUT.mkdir(exist_ok=True)
    bridge = PROJECT / "bridge"
    failed: list[str] = []
    for name in HOST_CPP_TESTS:
        source = PROJECT / f"tests/{name}.cpp"
        binary = OUT / f"{name}-test"
        log(f"\n=== {name} ===")
        compile_command = [
            "c++", "-std=c++17", "-O2", f"-I{bridge}",
            f"-I{PROJECT / 'core/platform'}", f"-I{PROJECT / 'core/host_fake'}",
            str(source), "-ldl", "-o", str(binary)
        ]
        if name == "retired_content":
            compile_command = [
                "c++", "-std=c++17", "-O2", f"-I{bridge}", str(source), "-o", str(binary)
            ]
        if name == "device_jni":
            # tests/host_jni comes first so the bridge header picks up the minimal host
            # stand-in instead of the Android jni.h, which does not compile against glibc.
            compile_command = [
                "c++", "-std=c++17", "-O2", f"-I{PROJECT / 'tests/host_jni'}",
                f"-I{bridge}", str(source), "-o", str(binary)
            ]
        log("+ " + " ".join(compile_command))
        compiled = subprocess.run(compile_command, cwd=BASE, capture_output=True, text=True)
        if compiled.returncode != 0:
            log("BUILD FAILED")
            log(compiled.stderr.strip()[-2000:])
            failed.append(name)
            continue
        executed = subprocess.run([str(binary)], cwd=BASE, capture_output=True, text=True)
        if executed.stdout.strip():
            log(executed.stdout.strip())
        if executed.returncode != 0:
            log(f"FAILED (exit {executed.returncode})")
            if executed.stderr.strip():
                log(executed.stderr.strip()[-2000:])
            failed.append(name)
        else:
            log("PASS")
    return failed


GROUP_TAGS = {"passed": "ok", "failed": "FEHLER", "skipped": "UEBERSPRUNGEN"}


def format_group_summary(groups: list[tuple[str, str, str]]) -> list[str]:
    """One aligned line per check group: (label, state, detail).

    "skipped" and "failed" get different words on purpose: a group that did not run is
    not a group that ran and passed, and reporting it as either would overstate what was
    verified. An unknown state raises instead of being rendered as something plausible.
    """
    tag_width = max(len(tag) for tag in GROUP_TAGS.values())
    label_width = max(len(label) for label, _, _ in groups)
    return [f"  [{GROUP_TAGS[state]:<{tag_width}}] {label.ljust(label_width)}  {detail}"
            for label, state, detail in groups]


def check_detail(state: str, passed_text: str, skip_reason: str) -> str:
    if state == "passed":
        return passed_text
    if state == "skipped":
        return f"{skip_reason} - nicht geprueft"
    return "fehlgeschlagen"


def run_host_cpp_tests() -> int:
    failed_cpp = run_cpp_boundary_tests()
    rust_state = run_rust_tests()
    abi_state = run_abi_smoke()
    bridge_state = run_bridge_compile()
    perf_state = run_perf_report_selftest()
    capture_state = run_capture_selftest()
    manifest_state = run_manifest_selftest()
    pinned_state = run_pinned_selftest()
    frame_state = run_frame_policy_selftest()
    lua_state = run_lua_harnesses()

    groups: list[tuple[str, str, str]] = [
        (f"C++-Grenztests ({len(HOST_CPP_TESTS)})",
         "failed" if failed_cpp else "passed",
         "fehlgeschlagen: " + ", ".join(failed_cpp) if failed_cpp else "bestanden"),
        ("Rust-Unit-Tests", rust_state, check_detail(rust_state, "bestanden", "cargo fehlt")),
        ("C++/Rust-ABI-Smoke", abi_state,
         check_detail(abi_state, "bestanden", "cargo fehlt")),
        ("Bridge-Cross-Compile", bridge_state,
         check_detail(bridge_state, "aarch64-linux-android29, -Werror", "kein NDK gefunden")),
        ("Performance-Auswertung", perf_state,
         check_detail(perf_state, "Selbsttest bestanden", "nicht gelaufen")),
        ("Geraeteerfassung", capture_state,
         check_detail(capture_state, "Selbsttest bestanden", "nicht gelaufen")),
        ("Ueberlagerungs-Manifest", manifest_state,
         check_detail(manifest_state, "Selbsttest bestanden", "nicht gelaufen")),
        ("Gepinnte Adressen", pinned_state,
         check_detail(pinned_state, "Selbsttest bestanden", "nicht gelaufen")),
        ("Frame-Zeit-Politik", frame_state,
         check_detail(frame_state, "Selbsttest bestanden", "nicht gelaufen")),
        ("Basis-APK-Pruefung", run_base_apk_selftest(), "Selbsttest"),
        (f"Lua-Harnesses ({len(LUA_HARNESSES)})", lua_state,
         check_detail(lua_state, "bestanden", "liblua5.4 fehlt")),
    ]
    broken = [label for label, state, _ in groups if state == "failed"]
    skipped = [label for label, state, _ in groups if state == "skipped"]

    log("\n=== Zusammenfassung ===")
    for line in format_group_summary(groups):
        log(line)
    log(f"\nErgebnis: {len(groups) - len(broken) - len(skipped)} bestanden, "
        f"{len(broken)} fehlgeschlagen, {len(skipped)} uebersprungen.")
    if skipped:
        log("Uebersprungen heisst nicht geprueft; diese Gruppen fehlen in der Abdeckung:")
        for label in skipped:
            log(f"  - {label}")

    log("\nNicht in diesem Modus enthalten (private Voraussetzungen noetig):")
    log("  - Linken von liblauncheq.so, Overlay-APK, APK-Verifikation (Basis-APK, JDK)")

    if broken:
        log(f"\n{len(broken)} Pruefgruppe(n) fehlgeschlagen.")
        return 1
    return 0


def build() -> None:
    missing = [r for r in check_prerequisites() if not r[0]]
    if missing:
        report_check()
        raise SystemExit("\nAbbruch: Voraussetzungen fehlen (siehe oben).")
    mirror_problems = check_mirrors()
    if mirror_problems:
        raise SystemExit("Abbruch: Spiegelprüfung fehlgeschlagen: " + "; ".join(mirror_problems))

    OUT.mkdir(exist_ok=True)

    run(sys.executable, WORK / "verify_gdroid_base.py")
    run(sys.executable, WORK / "run_lua_checks.py",
        WORK / "harness/test_hl2_grip_cache.lua",
        WORK / "harness/test_hl2_native_models.lua",
        WORK / "harness/test_hl2_equipment.lua",
        WORK / "harness/test_hl2_weapon_catalog.lua",
        WORK / "harness/test_native_pose_class.lua",
        WORK / "test_reload_client.lua", WORK / "harness/test_hl2_reload_refill.lua",
        WORK / "test_gquest_menu_navigation.lua")
    cargo("test")
    run("c++", "-std=c++17", "-O2", "-I" + str(PROJECT / "bridge"),
        PROJECT / "tests/native_fingers.cpp", "-ldl", "-o", OUT / "native-fingers-test")
    run(OUT / "native-fingers-test")
    run("c++", "-std=c++17", "-O2", "-I" + str(PROJECT / "bridge"),
        PROJECT / "tests/vr_lua.cpp", "-ldl", "-o", OUT / "vr-lua-test")
    run(OUT / "vr-lua-test")
    run("c++", "-std=c++17", "-O2", "-I" + str(PROJECT / "bridge"),
        PROJECT / "tests/retired_content.cpp", "-o", OUT / "retired-content-test")
    run(OUT / "retired-content-test")
    cargo("build", "--release")
    run("c++", "-std=c++17", "-I" + str(PROJECT / "include"), PROJECT / "tests/ffi_smoke.cpp",
        PROJECT / "target/release/libgquest_runtime.a", "-ldl", "-lpthread", "-lm",
        "-o", OUT / "ffi-smoke")
    run(OUT / "ffi-smoke")
    cargo("build", "--release", "--target", "aarch64-linux-android")
    run(NDK / "aarch64-linux-android29-clang++", "-shared", "-fPIC", "-O2",
        "-I" + str(PROJECT / "include"), PROJECT / "bridge/quest_engine_bridge.cpp",
        PROJECT / "target/aarch64-linux-android/release/libgquest_runtime.a",
        "-o", WORK / "liblauncheq.so", "-llog", "-ldl", "-lEGL", "-lGLESv3", "-landroid",
        # 16 KB pages: the rest of the package is already built for them (libclient.so has
        # p_align 16384) and targetSdk 35 makes it a requirement on Android 15 devices.
        # NDK 23 still defaults to 4096, so the alignment is asked for explicitly.
        "-Wl,-z,max-page-size=16384", "-Wl,-z,common-page-size=16384",
        "-Wl,--no-undefined", "-Wl,--exclude-libs,ALL", "-Wl,--no-as-needed",
        WORK / "gdroid-0.1.30-native/liblauncher.so", "-Wl,-soname,liblauncheq.so")
    run(sys.executable, WORK / "build_quest_lab.py")
    run(TOOLS / "zipalign", "-f", "-p", "4", WORK / "GMod-Quest-Lab-unsigned.apk",
        WORK / "GMod-Quest-Lab-aligned.apk")
    run(JAVA, "-jar", TOOLS / "lib/apksigner.jar", "sign", "--ks", KEYSTORE,
        "--ks-pass", "pass:android", "--key-pass", "pass:android",
        "--out", WORK / "Gquest.apk", WORK / "GMod-Quest-Lab-aligned.apk")
    run(sys.executable, WORK / "verify_gquest_package.py")

    apk = WORK / "Gquest.apk"
    baseline = BASE / "outputs/GDroid-0.1.30.apk"
    with zipfile.ZipFile(baseline) as before, zipfile.ZipFile(apk) as after:
        def content(z):
            return {n for n in z.namelist() if not n.startswith("META-INF/")}

        prefix = "assets/quest_lab_vr_content/"
        assert not content(before) - content(after), "Unexpected base APK member removal"
        added = sorted(content(after) - content(before))
        assert all(
            n.startswith(prefix) or n in {"assets/quest_lab_vr_content.tsv",
                                         "lib/arm64-v8a/liblauncheq.so"}
            for n in added
        )
        changed = [n for n in sorted(content(before) & content(after))
                   if before.read(n) != after.read(n)]
        assert set(changed) == {"AndroidManifest.xml", "classes.dex",
                               "lib/arm64-v8a/libclient.so"}, changed
        # New launcher, runtime payload, menu resources and every other native library
        # must come from official 0.1.30, never a mixture with the previous base.
        for n in content(before) - set(changed):
            assert before.read(n) == after.read(n), n
    shutil.copy2(apk, OUT / "Gquest.apk")
    report = dict(
        version="0.1.30-gquest", upstream_version="0.1.30", package="com.gmodvr.qvrx",
        rust_role="VR profiles and owned launcher arguments", engine="existing GDroid",
        renderer="existing libvrxr; no Hotham session",
        apk_sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
        rust_tests=5, cpp_rust_abi_smoke="passed", native_finger_wrapper_test="passed",
        vr_lua_compatibility_test="passed", changed_apk_payloads=changed,
        added_gquest_overlay_payloads=added,
        existing_models_engine_payloads=(
            "official 0.1.30 base; only audited client VR-player instruction patched; "
            "own bridge and Lua added"
        ),
        native_fingers=(
            "opt-in exact-build native blend adapter; original left/root/curl sampling "
            "retained"
        ),
        signature="verified", zip_crc="passed", quest_test="pending")
    (OUT / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k != "added_gquest_overlay_payloads"}, indent=2))


def run_units() -> int:
    """C++ boundary tests and the tool self-tests in one fast run.

    Nothing here needs private data, a headset, an NDK or Lua. Exit status is the whole
    answer: 0 when every group passed, 1 when any group failed. A group is never reported
    as passed unless it actually ran.
    """
    failed_cpp = run_cpp_boundary_tests()
    groups: list[tuple[str, str, str]] = [
        (f"C++-Grenztests ({len(HOST_CPP_TESTS)})",
         "failed" if failed_cpp else "passed",
         "fehlgeschlagen: " + ", ".join(failed_cpp) if failed_cpp else "bestanden"),
        ("Performance-Auswertung", run_perf_report_selftest(), "Selbsttest"),
        ("Geraeteerfassung", run_capture_selftest(), "Selbsttest"),
        ("Ueberlagerungs-Manifest", run_manifest_selftest(), "Selbsttest"),
        ("Gepinnte Adressen", run_pinned_selftest(), "Selbsttest"),
        ("Frame-Zeit-Politik", run_frame_policy_selftest(), "Selbsttest"),
        ("Basis-APK-Pruefung", run_base_apk_selftest(), "Selbsttest"),
    ]
    broken = [label for label, state, _ in groups if state == "failed"]
    log("\n=== Zusammenfassung ===")
    for line in format_group_summary(groups):
        log(line)
    log(f"\nErgebnis: {len(groups) - len(broken)}/{len(groups)} Pruefgruppen bestanden.")
    log("Exit 0 = alles bestanden, Exit 1 = mindestens eine Gruppe fehlgeschlagen.")
    return 1 if broken else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="GQuest build: GDroid overlay APK with own bridge and VR content.")
    parser.add_argument("--check", action="store_true",
                        help="only report missing prerequisites and mirror drift")
    parser.add_argument("--tests", action="store_true",
                        help="run the boundary tests that need no private data")
    parser.add_argument("--units", action="store_true",
                        help="only the C++ boundary tests and tool self-tests "
                             "(no NDK, Rust or Lua); exit 0 = all passed, 1 = failed")
    args = parser.parse_args(argv)

    if args.check:
        return report_check()
    if args.tests:
        return run_host_cpp_tests()
    if args.units:
        return run_units()
    build()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
