#!/usr/bin/env python3
"""Judge the log of a real first start: launcher readiness, content install, device detection,
hand smoothing, hand pipeline, weapon mechanics and gestures.

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

# Weapon mechanics. The total is chamber plus magazine; it is the number the engine shows as
# clip, so it may only ever go down except when a magazine goes back in or a reload happens.
MECH_READY = re.compile(r"GQUEST_MECH ready")
MECH_EVENT = re.compile(
    r"GQUEST_MECH action=(\w[\w-]*) class=(\S+) chamber=(\d+) mag=(\d+) total=(\d+) "
    r"safety=(\w+) slide=(\w+) inserted=(\w+) stored=(\d+)(?: note=(.*))?$")
MECH_REFUSED = re.compile(r"GQUEST_MECH write refused class=(\S+) reason=(.*)$")
MECH_STATE = re.compile(
    r"GQUEST_MECH STATE class=(\S+) kind=(\S+) action=(\S+) capacity=(\d+) chamber=(\d+) "
    r"mag=(\d+) safety=(\w+) slide=(\w+) inserted=(\w+) stored=(\d+)")
MECH_GROWS_ONLY = {"init", "mag-in", "reload"}

GESTURE_READY = re.compile(r"GQUEST_MECHGESTURE ready")
GESTURE_INACTIVE = re.compile(r"GQUEST_MECHGESTURE action_inactive=(\S+)")
GESTURE_MAG = re.compile(r"GQUEST_MECHGESTURE mag class=(\S+)")
GESTURE_RACK = re.compile(r"GQUEST_MECHGESTURE rack class=(\S+) distance=([\d.]+) travel=([\d.]+)")

HANDS_STATE = re.compile(r"GQUEST_HANDS hand=(left|right) state=(\w+) drops=(\d+)")


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

    # 5. Hand pipeline: did a hand get held (sample lost) and did it come back?
    hand_states: dict[str, tuple[str, int]] = {}
    for line in lines:
        match = HANDS_STATE.search(line)
        if match:
            hand, state, drops = match.group(1), match.group(2), int(match.group(3))
            seen = hand_states.get(hand)
            hand_states[hand] = (state, (seen[1] if seen else 0) + drops)
    if hand_states:
        held = [name for name, (state, _) in hand_states.items() if state == "held"]
        drops = sum(count for _, (_, count) in hand_states.items())
        hands = ", ".join(f"{name}={state}" for name, (state, _) in sorted(hand_states.items()))
        if held:
            findings.append((WARN, "Hand-Pipeline",
                             f"{hands}; gehalten am Ende: {', '.join(held)} - die letzte Probe "
                             f"war unbrauchbar, das Tracking brach ab (Feld bleibt stehen statt zu "
                             f"verschwinden)"))
        else:
            findings.append((OK, "Hand-Pipeline",
                             f"{hands}; {drops} Probe(n) gehalten und wieder aufgefangen"))
    else:
        findings.append((UNKNOWN, "Hand-Pipeline",
                         "keine GQUEST_HANDS-Zeile - Provider lief nicht, veroeffentlichte nichts "
                         "oder erreicht logcat nicht"))

    # 6. Weapon mechanics: only a running state machine proves the hook grips.
    refused = [l for l in lines if MECH_REFUSED.search(l)]
    events = [m for m in (MECH_EVENT.search(l) for l in lines) if m]
    for line in refused[:3]:
        match = MECH_REFUSED.search(line)
        findings.append((FAIL, "Mechanik",
                         f"Schreibvorgang abgelehnt ({match.group(1)}): {match.group(2).strip()} - "
                         f"die Waffe folgt der Engine, nicht dem Modell"))
    states_lines = [m for m in (MECH_STATE.search(l) for l in lines) if m]
    for match in states_lines[:2]:
        findings.append((OK, "Mechanik",
                         f"Zustand {match.group(1)}: {match.group(2)}, Kapazitaet "
                         f"{match.group(4)}, Kammer {match.group(5)}, Magazin {match.group(6)}"))
    if not events and not states_lines and not refused:
        if any(MECH_READY.search(l) for l in lines):
            findings.append((UNKNOWN, "Mechanik",
                             "Modul geladen, aber kein Zustandswechsel - nie geschossen, nie "
                             "nachgeladen oder der Hook greift nicht"))
        else:
            findings.append((UNKNOWN, "Mechanik",
                             "keine GQUEST_MECH-Zeile - Modul nicht geladen (dann bleibt alles "
                             "Retail-Verhalten)"))
    else:
        previous_total: dict[str, int] = {}
        problems: list[str] = []
        counts: dict[str, int] = {}
        for match in events:
            (action, klass, chamber, magazine, total, _safety, _slide, _inserted, _stored,
             _note) = match.groups()
            chamber, magazine, total = int(chamber), int(magazine), int(total)
            counts[action] = counts.get(action, 0) + 1
            if chamber + magazine != total:
                problems.append(f"{klass}/{action}: Kammer {chamber} + Magazin {magazine} != "
                                f"Summe {total}")
            before = previous_total.get(klass)
            if before is not None:
                if action == "fire" and total != before - 1:
                    problems.append(f"{klass}: Schuss zaehlte {before} -> {total}, erwartet "
                                    f"{before - 1}")
                elif total > before and action not in MECH_GROWS_ONLY:
                    problems.append(f"{klass}/{action}: Munition {before} -> {total} ohne "
                                    f"Magazinwechsel")
            previous_total[klass] = total
        for problem in problems[:4]:
            findings.append((FAIL, "Mechanik", problem))
        shots = counts.get("fire", 0)
        blocked = counts.get("blocked", 0)
        detail = (f"{shots} Schuss, {blocked} blockiert, "
                  f"{counts.get('rack', 0)} durchgeladen, "
                  f"{counts.get('mag-out', 0)} Magazin raus, {counts.get('mag-in', 0)} rein, "
                  f"{counts.get('safety', 0)} Sicherung")
        if not problems:
            if shots == 0:
                findings.append((WARN, "Mechanik",
                                 f"{detail} - kein einziger Schuss verbucht: bei dieser Waffe "
                                 f"greift der Hook nicht, oder es wurde nicht geschossen"))
            else:
                findings.append((OK, "Mechanik", detail))

    # 7. Gestures: a missing action name is the one failure that kills the gesture path.
    inactive = [m.group(1) for m in (GESTURE_INACTIVE.search(l) for l in lines) if m]
    for name in dict.fromkeys(inactive):
        findings.append((WARN, "Gesten",
                         f"Aktion '{name}' ist in dieser Session nicht verfuegbar - diese Taste "
                         f"loest nichts aus; Konsole (gquest_mech_*) bleibt der Weg"))
    mags = [m for m in (GESTURE_MAG.search(l) for l in lines) if m]
    racks = [m for m in (GESTURE_RACK.search(l) for l in lines) if m]
    if racks or mags:
        detail = f"{len(mags)} Magazin-Geste(n), {len(racks)} Rack-Geste(n)"
        if racks:
            last = racks[-1]
            detail += (f"; letzte Rack-Geste Abstand {float(last.group(2)):g}, "
                       f"Weg {float(last.group(3)):g}")
        findings.append((OK, "Gesten", detail))
    elif inactive:
        # The warning above already names the cause; a second, vaguer UNBEKANNT would hide it.
        pass
    elif any(GESTURE_READY.search(l) for l in lines):
        findings.append((UNKNOWN, "Gesten",
                         "Modul geladen, aber keine Geste ausgeloest - nicht versucht oder "
                         "Schwellen zu eng (gquest_mech_reach / gquest_mech_travel)"))
    else:
        findings.append((UNKNOWN, "Gesten", "keine GQUEST_MECHGESTURE-Zeile - Modul nicht geladen"))

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


MECHANICS = """\
11-15 10:00:02.000  1000  1000 I GQUEST  : GQUEST_MECH ready: gquest_mech_state / _rack / _mag / _reload / _safety
11-15 10:00:02.100  1000  1000 I GQUEST  : GQUEST_MECH action=init class=weapon_pistol chamber=1 mag=17 total=18 safety=false slide=false inserted=true stored=0
11-15 10:00:03.000  1000  1000 I GQUEST  : GQUEST_MECH action=fire class=weapon_pistol chamber=1 mag=16 total=17 safety=false slide=false inserted=true stored=0
11-15 10:00:04.000  1000  1000 I GQUEST  : GQUEST_MECH action=mag-out class=weapon_pistol chamber=1 mag=0 total=1 safety=false slide=true inserted=false stored=16
11-15 10:00:05.000  1000  1000 I GQUEST  : GQUEST_MECH action=mag-in class=weapon_pistol chamber=1 mag=16 total=17 safety=false slide=true inserted=true stored=0
11-15 10:00:05.500  1000  1000 I GQUEST  : GQUEST_MECH action=rack class=weapon_pistol chamber=1 mag=15 total=16 safety=false slide=false inserted=true stored=0
11-15 10:00:06.000  1000  1000 I GQUEST  : GQUEST_MECHGESTURE ready: eject action drops/inserts the magazine, support hand racks
11-15 10:00:07.000  1000  1000 I GQUEST  : GQUEST_MECHGESTURE mag class=weapon_pistol
11-15 10:00:08.000  1000  1000 I GQUEST  : GQUEST_MECHGESTURE rack class=weapon_pistol distance=3.20 travel=5.10
11-15 10:00:09.000  1000  1000 I GQUEST  : GQUEST_HANDS hand=left state=ok drops=0
11-15 10:00:09.100  1000  1000 I GQUEST  : GQUEST_HANDS hand=right state=ok drops=2
"""

GOOD = GOOD + MECHANICS


def selftest() -> int:
    cases = [
        ("vollstaendiges Log", GOOD, 0, None),
        ("Munition erfunden", GOOD.replace(
            "action=rack class=weapon_pistol chamber=1 mag=15 total=16",
            "action=rack class=weapon_pistol chamber=1 mag=19 total=20"), 1, "ohne Magazinwechsel"),
        ("Schuss ohne Verbrauch", GOOD.replace(
            "action=fire class=weapon_pistol chamber=1 mag=16 total=17",
            "action=fire class=weapon_pistol chamber=1 mag=15 total=16"), 1, "Schuss zaehlte"),
        ("Schreibvorgang verweigert", GOOD +
         "11-15 10:00:10.000  1000  1000 I GQUEST  : GQUEST_MECH write refused class=weapon_pistol reason=clip write failed\n",
         1, "Schreibvorgang abgelehnt"),
        ("Taste nicht verfuegbar", GOOD +
         "11-15 10:00:10.000  1000  1000 I GQUEST  : GQUEST_MECHGESTURE action_inactive=rack\n",
         0, "nicht verfuegbar"),
        ("Hand bleibt haengen", GOOD.replace(
            "GQUEST_HANDS hand=right state=ok drops=2",
            "GQUEST_HANDS hand=right state=held drops=2"), 0, "gehalten am Ende"),
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
          "Installation, Launcher-Stop, erfundene Munition, ein verweigerter Waffenschreibvorgang "
          "und eine Stufe mit falscher Zeitkonstante scheitern; unbekanntes Geraet, fehlende "
          "Geste und eine haengende Hand sind Warnungen; ein Log ohne Marker ergibt Exit 2")
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
