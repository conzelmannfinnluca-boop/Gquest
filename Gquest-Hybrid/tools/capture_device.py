#!/usr/bin/env python3
"""Capture the real headset identity and record it in docs/measurements/device-identity.md.

Why two sources: Horizon OS runs apps in *compatibility mode* when the app's manifest
does not list the physical headset, and then device-identification APIs report an older
model (Meta, "Compatibility mode"). Meta explicitly warns not to use `Build.MODEL` to
decide anything about capabilities. So a value reported from inside the app is not proof
of the hardware, while `adb shell getprop` runs outside the app process and is not
subject to the per-app compatibility model.

This script therefore compares both and states whether the in-app detection agrees:

  physical  ro.product.model / ro.product.device via adb shell
  in-app    the bridge log line "DEVICE detected=<id> model='...' device='...'"

Both are classified with the same C++ classifier the bridge uses (tools/device_id.cpp),
so a second implementation cannot silently disagree with the shipped one.

Usage:
    python3 Gquest-Hybrid/tools/capture_device.py                      # both sources
    python3 Gquest-Hybrid/tools/capture_device.py --adb ~/platform-tools/adb
    python3 Gquest-Hybrid/tools/capture_device.py --model "Quest 3S" --device panther
    python3 Gquest-Hybrid/tools/capture_device.py --record docs/measurements/device-identity.md

Exit codes: 0 = captured, 1 = contradiction (detection would pick another profile),
2 = nothing captured, 3 = self-test failed.
"""
import argparse
import datetime
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BASE = PROJECT.parent
OUT = PROJECT / "dist"
HEADER = ("| Physisch (Build.MODEL) | Build.DEVICE | klassifiziert | In-App gemeldet "
          "| Urteil | Erfasst am |")
SEPARATOR = "|---|---|---|---|---|---|"
LOG_LINE = re.compile(r"DEVICE detected=(\w+) model='([^']*)' device='([^']*)'")


def build_helper() -> Path:
    """Compile the classifier driver once; returns the binary path."""
    OUT.mkdir(parents=True, exist_ok=True)
    binary = OUT / "device_id"
    source = PROJECT / "tools/device_id.cpp"
    header = PROJECT / "bridge/gquest_device_profile.h"
    newest = max(source.stat().st_mtime, header.stat().st_mtime)
    if binary.exists() and binary.stat().st_mtime >= newest:
        return binary
    command = ["c++", "-std=c++17", "-O2", f"-I{PROJECT / 'bridge'}", str(source),
               "-o", str(binary)]
    built = subprocess.run(command, capture_output=True, text=True)
    if built.returncode != 0:
        raise RuntimeError(f"device_id baut nicht: {built.stderr.strip()[-800:]}")
    return binary


def classify(model: str, device: str) -> str:
    """Ask the C++ classifier. 'unknown' is a valid answer, not an error."""
    helper = build_helper()
    result = subprocess.run([str(helper), model, device], capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(f"device_id fehlgeschlagen: {result.stderr.strip()}")
    return result.stdout.strip() or "unknown"


def adb_shell(adb: str, *arguments: str) -> str:
    result = subprocess.run([adb, *arguments], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout).strip() or "adb fehlgeschlagen")
    return result.stdout.strip()


def physical(adb: str) -> tuple[str, str]:
    """Values as the system reports them outside the app process."""
    return (adb_shell(adb, "shell", "getprop", "ro.product.model"),
            adb_shell(adb, "shell", "getprop", "ro.product.device"))


def in_app(adb: str) -> tuple[str, str, str] | None:
    """The bridge's own log line, if the app has been started since the buffer was cleared."""
    text = adb_shell(adb, "logcat", "-d")
    matches = LOG_LINE.findall(text)
    return matches[-1] if matches else None


def verdict(physical_id: str, app_id: str | None) -> str:
    if app_id is None:
        return "In-App-Wert fehlt - App starten und erneut erfassen"
    if physical_id == app_id:
        return "konsistent"
    if app_id == "unknown":
        return "App erkennt das Geraet nicht - gespeichertes Profil bleibt"
    return ("WIDERSPRUCH - vermutlich Compatibility Mode; App-seitige Erkennung "
            "nennt ein anderes Modell")


def format_row(model: str, device: str, physical_id: str, app_id: str | None,
               when: str) -> str:
    return (f"| `{model or '-'}` | `{device or '-'}` | `{physical_id}` "
            f"| `{app_id or '-'}` | {verdict(physical_id, app_id)} | {when} |")


def write_record(path: Path, row: str, key: str) -> None:
    """Append the row, replacing an earlier row with the same physical identity."""
    lines = path.read_text().splitlines() if path.exists() else []
    if HEADER not in lines:
        lines = [line for line in lines if line.strip()] + ["", "## Erfasste Werte", "",
                                                           HEADER, SEPARATOR]
    def is_same_headset(line: str) -> bool:
        if not line.startswith("|"):
            return False
        columns = line.split("|")
        return len(columns) > 1 and columns[1].strip() == f"`{key}`"

    kept = [line for line in lines if not is_same_headset(line)]
    kept.append(row)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(kept) + "\n")


def run(adb: str | None, model: str | None, device: str | None,
        record: Path | None) -> int:
    if model is not None:
        physical_model, physical_device = model, device or ""
        source = "manuell"
    elif adb:
        physical_model, physical_device = physical(adb)
        source = "adb"
    else:
        print("Weder --adb noch --model angegeben.")
        return 2

    physical_id = classify(physical_model, physical_device)
    reported = in_app(adb) if adb else None
    app_id = reported[0] if reported else None
    when = datetime.date.today().isoformat()

    print(f"Quelle: {source}")
    print(f"  Build.MODEL  = {physical_model or '(leer)'}")
    print(f"  Build.DEVICE = {physical_device or '(leer)'}")
    print(f"  klassifiziert als: {physical_id}")
    if reported:
        print(f"  In-App gemeldet:   {reported[0]} (model='{reported[1]}' device='{reported[2]}')")
    elif adb:
        print("  In-App gemeldet:   (keine DEVICE-Zeile im Logcat)")
    print(f"  Urteil: {verdict(physical_id, app_id)}")

    if record is not None:
        key = physical_model or physical_device
        write_record(record, format_row(physical_model, physical_device, physical_id,
                                       app_id, when), key)
        print(f"  gespeichert in {record}")

    if physical_id == "unknown":
        return 2
    if app_id is not None and app_id != "unknown" and app_id != physical_id:
        return 1
    return 0


def run_self_test() -> int:
    """Stub adb + synthetic log: proves the plumbing without a headset."""
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        stub = root / "adb"
        stub.write_text(
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  *getprop*ro.product.model*) echo 'Quest 3S' ;;\n"
            "  *getprop*ro.product.device*) echo 'panther' ;;\n"
            "  *logcat*) echo \"11-14 19:00:00.000 I/GQUEST: DEVICE detected=quest3s "
            "model='Quest 3S' device='panther'\" ;;\n"
            "  *) echo 'unexpected' >&2; exit 1 ;;\n"
            "esac\n")
        stub.chmod(0o755)

        if classify("Quest 3S", "panther") != "quest3s":
            failures.append("Classifier liefert nicht quest3s")
        if classify("Quest 3", "eureka") != "quest3":
            failures.append("Classifier liefert nicht quest3")
        if classify("Oculus_Quest_3S", "") != "quest3s":
            failures.append("Oculus-Schreibweise wird nicht erkannt")
        if classify("Quest 30", "") != "unknown":
            failures.append("Fast-Treffer wird faelschlich erkannt")

        model, device = physical(str(stub))
        if (model, device) != ("Quest 3S", "panther"):
            failures.append(f"getprop-Pfad falsch: {model}/{device}")
        reported = in_app(str(stub))
        if reported is None or reported[0] != "quest3s":
            failures.append(f"Logcat-Zeile nicht gelesen: {reported}")

        if verdict("quest3s", "quest3s") != "konsistent":
            failures.append("gleiche IDs muessen konsistent sein")
        if "WIDERSPRUCH" not in verdict("quest3s", "quest3"):
            failures.append("unterschiedliche IDs muessen Widerspruch melden")
        if "fehlt" not in verdict("quest3s", None):
            failures.append("fehlender In-App-Wert muss benannt werden")

        # Der volle Pfad inklusive Protokollzeile, zweimal, damit Ersetzen statt
        # Anhaengen geprueft ist.
        record = root / "device-identity.md"
        for _ in range(2):
            run(str(stub), None, None, record)
        text = record.read_text()
        rows = [line for line in text.splitlines()
                if line.startswith("| `Quest 3S`")]
        if len(rows) != 1:
            failures.append(f"Erwartet genau eine Zeile, gefunden {len(rows)}")
        if text.count(HEADER) != 1:
            failures.append("Kopfzeile wurde mehrfach geschrieben")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 3
    print("PASS Geraeteerfassung: Klassifizierung inkl. Oculus-Schreibweise, "
          "getprop-Pfad, Logcat-Zeile, Widerspruchs-Urteil, idempotentes Protokoll")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb", help="Pfad zu adb")
    parser.add_argument("--model", default=None, help="Build.MODEL ohne adb vorgeben")
    parser.add_argument("--device", default=None, help="Build.DEVICE ohne adb vorgeben")
    parser.add_argument("--record", type=Path, default=None,
                        help="Markdown-Datei, in die die Zeile geschrieben wird")
    parser.add_argument("--test", action="store_true", help="Selbsttest ohne Headset")
    arguments = parser.parse_args()

    if arguments.test:
        return run_self_test()
    adb = arguments.adb if arguments.model is None else None
    try:
        return run(adb, arguments.model, arguments.device, arguments.record)
    except (RuntimeError, subprocess.SubprocessError, OSError) as error:
        print(f"Fehler: {error}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
