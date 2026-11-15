#!/usr/bin/env python3
"""Judge the log of a real first start: launcher readiness, content install, device detection,
hand smoothing.

The hardware test is the step this project cannot do itself, so the log is the only evidence it
ever produces. Reading it by eye invites the usual mistake: "no CONTENT line" looks the same as
"content installed fine" if nobody looks for it. This script asks for each area explicitly and
says UNBEKANNT when the line is missing.

    adb logcat -d > quest-start.log
    python3 Gquest-Hybrid/tools/evaluate_hardware_log.py quest-start.log
    adb logcat -d | python3 Gquest-Hybrid/tools/evaluate_hardware_log.py -

Exit codes: 0 = no failure (unknown areas are listed and named), 1 = at least one failure,
2 = none of the expected lines were found at all (wrong file or wrong filter).

The smoothing check compares the logged level against the time constant the module should have
for it, so a profile that says strong while the filter runs mild is caught instead of reported as
"a level was set".
"""
from __future__ import annotations

import argparse
import re
import sys

OK, FAIL, WARN, UNKNOWN = "ok", "fail", "warn", "unknown"

# What the module believes each level means; a log line disagreeing with this is a real defect.
LEVELS = {"off": 0.0, "mild": 0.03, "strong": 0.06}

START_READY = re.compile(r"GQUEST_RUST READY abi=(\d+) eye=(\S+) ffr=(\d+) refresh=(\d+)")
START_STOP = re.compile(r"GQUEST_RUST STOP (.+)$")
CONTENT_READY = re.compile(r"CONTENT ready=(\d+) installed=(\d+) existing=(\d+)(?: root=(\S+))?")
CONTENT_REJECTED = re.compile(r"CONTENT manifest rejected: (.+)$")
DEVICE_DETECTED = re.compile(r"DEVICE detected=(\S+) model='([^']*)' device='([^']*)'")
DEVICE_UNRECOGNIZED = re.compile(r"DEVICE unrecognized model='([^']*)' device='([^']*)'")
DEVICE_WARN = re.compile(r"DEVICE WARN (.+)$")
DEVICE_NO_BUILD = re.compile(r"DEVICE Build class unavailable")
HANDSMOOTH = re.compile(r"GQUEST_HANDSMOOTH level=(\w+) tau=([\d.]+) enabled=(true|false)")


def classify_level(level: str, tau: float, enabled: bool) -> tuple[str, str]:
    """Return (state, detail) for one smoothing line."""
    expected = LEVELS.get(level)
    if expected is None:
        return FAIL, f"unbekannte Stufe '{level}'"
    if abs(tau - expected) > 1e-6:
        return FAIL, f"Stufe {level} meldet tau={tau:g}, erwartet {expected:g} - Profil und Modul sind sich uneins"
    if enabled != (expected > 0):
        return FAIL, f"Stufe {level} meldet enabled={enabled}, erwartet {expected > 0}"
    return OK, f"Stufe {level}, tau={tau:g}, Filter {'an' if enabled else 'aus'}"


def evaluate(text: str) -> tuple[list[tuple[str, str, str]], int]:
    """Return findings as (state, area, detail) plus the exit code."""
    lines = text.splitlines()
    findings: list[tuple[str, str, str]] = []

    # 1. Launcher start
    ready = next((m for m in (START_READY.search(l) for l in lines) if m), None)
    stop = next((m for m in (START_STOP.search(l) for l in lines) if m), None)
    if stop:
        findings.append((FAIL, "Start", "Launcher abgebrochen: " + stop.group(1).strip()))
    elif ready:
        findings.append((OK, "Start",
                         f"ABI {ready.group(1)}, eye {ready.group(2)}, FFR {ready.group(3)}, "
                         f"{ready.group(4)} Hz"))
    else:
        findings.append((UNKNOWN, "Start", "keine GQUEST_RUST-Zeile"))

    # 2. Content installer
    rejected = next((m for m in (CONTENT_REJECTED.search(l) for l in lines) if m), None)
    content = next((m for m in (CONTENT_READY.search(l) for l in lines) if m), None)
    if rejected:
        findings.append((FAIL, "Content", "Manifest abgelehnt: " + rejected.group(1).strip()))
    if content:
        ok_flag, installed, existing = (int(content.group(i)) for i in (1, 2, 3))
        if ok_flag != 1:
            findings.append((FAIL, "Content",
                             f"Installation abgebrochen (ready=0), {installed} geschrieben, "
                             f"{existing} vorhanden - das Manifest endet vorzeitig"))
        else:
            detail = f"{installed} geschrieben, {existing} bereits vorhanden"
            if installed == 0 and existing == 0:
                findings.append((WARN, "Content",
                                 "Installation lief, hat aber nichts geschrieben oder gefunden"))
            else:
                findings.append((OK, "Content", detail))
    elif not rejected:
        findings.append((UNKNOWN, "Content", "keine CONTENT-Zeile - Installer lief nicht oder loggte nichts"))

    # 3. Device detection
    detected = next((m for m in (DEVICE_DETECTED.search(l) for l in lines) if m), None)
    unrecognized = next((m for m in (DEVICE_UNRECOGNIZED.search(l) for l in lines) if m), None)
    if detected:
        findings.append((OK, "Geraet", f"erkannt als {detected.group(1)}"))
    elif unrecognized:
        findings.append((WARN, "Geraet",
                         f"Modell '{unrecognized.group(1)}' / device '{unrecognized.group(2)}' "
                         f"nicht klassifiziert - gespeichertes Profil bleibt aktiv"))
    elif DEVICE_NO_BUILD.search(text) or any(DEVICE_NO_BUILD.search(l) for l in lines):
        findings.append((FAIL, "Geraet", "Build-Klasse nicht lesbar - Erkennung ausgefallen"))
    else:
        findings.append((UNKNOWN, "Geraet", "keine DEVICE-Zeile"))
    warnings = [l.strip() for l in lines if DEVICE_WARN.search(l)]
    for line in warnings[:3]:
        findings.append((WARN, "Geraet", DEVICE_WARN.search(line).group(1).strip()))

    # 4. Hand smoothing: the level that really reached the filter
    smoothing = next((m for m in (HANDSMOOTH.search(l) for l in lines) if m), None)
    if smoothing:
        state, detail = classify_level(smoothing.group(1), float(smoothing.group(2)),
                                        smoothing.group(3) == "true")
        findings.append((state, "Glaettung", detail))
    else:
        findings.append((UNKNOWN, "Glaettung",
                         "keine GQUEST_HANDSMOOTH-Zeile - Lua-print erreicht logcat nicht, "
                         "oder das Modul wurde nie geladen"))

    states = [s for s, _, _ in findings]
    if all(s == UNKNOWN for s in states) and not ready:
        return findings, 2
    return findings, 1 if FAIL in states else 0


def print_report(findings: list[tuple[str, str, str]]) -> None:
    symbols = {OK: "[ok]     ", FAIL: "[FEHLER] ", WARN: "[warnung]", UNKNOWN: "[UNBEKANNT]"}
    for state, area, detail in findings:
        print(f"  {symbols[state]} {area}: {detail}")


# --- self-test -------------------------------------------------------------------------

GOOD = """\
11-15 10:00:01.001  1000  1000 I GQUEST  : GQUEST_RUST READY abi=1 eye=right ffr=2 refresh=72 loaded=2 argc=4
11-15 10:00:01.100  1000  1000 I GQUEST  : CONTENT ready=1 installed=16 existing=3 root=/storage/emulated/0/Android/data/com.gmodvr.qvrx/files/user/vr_content/
11-15 10:00:01.200  1000  1000 I GQUEST  : DEVICE detected=quest3 model='Quest 3' device='eureka' supported='quest3,quest3s'
11-15 10:00:01.300  1000  1000 I GQUEST  : GQUEST_HANDSMOOTH level=mild tau=0.030 enabled=true
"""


def selftest() -> int:
    cases = [
        ("vollstaendiges Log", GOOD, 0, None),
        ("Manifest abgelehnt", GOOD.replace(
            "CONTENT ready=1 installed=16 existing=3 root=/storage/emulated/0/Android/data/com.gmodvr.qvrx/files/user/vr_content/",
            "CONTENT manifest rejected: ParentTraversal"), 1, "ParentTraversal"),
        ("Installation abgebrochen", GOOD.replace(
            "CONTENT ready=1 installed=16 existing=3", "CONTENT ready=0 installed=8 existing=0"), 1,
         "abgebrochen"),
        ("unbekanntes Geraet", GOOD.replace(
            "DEVICE detected=quest3 model='Quest 3' device='eureka' supported='quest3,quest3s'",
            "DEVICE unrecognized model='Quest 9' device='orca'; saved profile kept"), 0,
         "nicht klassifiziert"),
        ("Launcher-Stop", GOOD.replace(
            "GQUEST_RUST READY abi=1 eye=right ffr=2 refresh=72 loaded=2 argc=4",
            "GQUEST_RUST STOP incompatible runtime ABI"), 1, "incompatible runtime ABI"),
        ("Stufe und Zeitkonstante uneins", GOOD.replace(
            "level=mild tau=0.030", "level=strong tau=0.030"), 1, "sind sich uneins"),
        ("keine Zeilen", "irgendein anderes Log\nohne Marker\n", 2, None),
    ]
    failures = []
    for name, text, expected_exit, expected_text in cases:
        findings, code = evaluate(text)
        if code != expected_exit:
            failures.append(f"{name}: Exit {code}, erwartet {expected_exit}")
        if expected_text and not any(expected_text in detail for _, _, detail in findings):
            failures.append(f"{name}: kein Befund enthaelt {expected_text!r}")
        if expected_exit == 0 and expected_text is None:
            states = [s for s, _, _ in findings]
            if UNKNOWN in states:
                failures.append(f"{name}: unerwarteter UNBEKANNT-Befund")
    if failures:
        print("FAIL Log-Auswertung Selbsttest:")
        for line in failures:
            print("  " + line)
        return 1
    print("PASS Log-Auswertung: vollstaendiges Log besteht; abgelehntes Manifest, abgebrochene "
          "Installation, Launcher-Stop und eine Stufe mit falscher Zeitkonstante scheitern; ein "
          "unbekanntes Geraet ist eine Warnung; ein Log ohne Marker ergibt Exit 2")
    return 0


def main(argv: list[str]) -> int:
    if "--test" in argv[1:]:
        return selftest()
    parser = argparse.ArgumentParser(description="Quest-Log eines ersten Starts auswerten.")
    parser.add_argument("log", nargs="?", default="-", help="Logdatei oder - fuer stdin")
    parser.add_argument("--test", action="store_true", help="Selbsttest statt Auswertung")
    args = parser.parse_args(argv[1:])
    text = sys.stdin.read() if args.log == "-" else open(args.log, encoding="utf-8", errors="replace").read()
    findings, code = evaluate(text)
    print(f"Log: {args.log} ({len(text.splitlines())} Zeilen)")
    print()
    print_report(findings)
    print()
    if code == 2:
        print("Ergebnis: keine der erwarteten Zeilen gefunden - falsches Log oder falscher Filter "
              "(Exit 2).")
    elif code == 1:
        print("Ergebnis: mindestens ein Befund ist ein Fehler (Exit 1).")
    else:
        unknown = [area for state, area, _ in findings if state == UNKNOWN]
        print("Ergebnis: keine Fehler (Exit 0)."
              + (f" Unbekannt geblieben: {', '.join(unknown)}." if unknown else ""))
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
