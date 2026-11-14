#!/usr/bin/env python3
"""Evaluate GQuest performance runs according to docs/PERF_PROTOCOL.md.

The protocol fixes two things that are easy to get wrong by hand, and this script is the
implementation of both:

* the noise threshold (section 7.3): two profiles count as distinguishable only when
  their per-run p95 ranges do not overlap. Overlapping means "not shown", never
  "roughly equal".
* the decision rule (section 7.4): suitable / borderline / unsuitable, measured against
  the frame budget of the refresh rate that was actually configured.

Input is one CSV per run, as the protocol stores them (`runs/<geraet>-<stufe>-<n>.csv`).
Output is a markdown table per device, ready for docs/measurements/<geraet>.md, plus the
pairwise comparisons.

Usage:
    python3 Gquest-Hybrid/tools/perf_report.py runs/*.csv
    python3 Gquest-Hybrid/tools/perf_report.py runs/*.csv --window 512 --min-runs 3
    python3 Gquest-Hybrid/tools/perf_report.py --test      # synthetic self-test

No third-party packages. Exit codes: 0 = evaluated, 2 = input problem, 3 = self-test
failure.
"""
import argparse
import csv
import statistics
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

REQUIRED = ("ms_p50", "ms_p95", "fps_1pct_low", "hitches", "under_budget_pct", "target_hz")
BORDERLINE_FACTOR = 1.15
HITCH_LIMIT_PER_MINUTE = 1.0


@dataclass
class Run:
    name: str
    device: str
    tier: str
    index: str
    rows: list[dict] = field(default_factory=list)


@dataclass
class Group:
    device: str
    tier: str
    target_hz: float
    runs: list[dict]           # one summary dict per run
    window_frames: int
    dropped_rows: int = 0

    @property
    def budget_ms(self) -> float:
        return 1000.0 / self.target_hz

    def median(self, key: str) -> float:
        return statistics.median(run[key] for run in self.runs)

    def spread(self, key: str) -> tuple[float, float]:
        values = [run[key] for run in self.runs]
        return min(values), max(values)


def parse_name(path: Path) -> tuple[str, str, str]:
    """`quest3s-ausgewogen-1.csv` -> (quest3s, ausgewogen, 1)."""
    stem = path.stem
    parts = stem.split("-")
    if len(parts) >= 3 and parts[-1].isdigit():
        return parts[0], "-".join(parts[1:-1]), parts[-1]
    return stem, "", stem


def read_run(path: Path) -> Run:
    """Read one CSV. Header order is taken from the file, not assumed."""
    device, tier, index = parse_name(path)
    run = Run(path.stem, device, tier, index)
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [column for column in REQUIRED if column not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(f"{path.name}: Spalten fehlen: {', '.join(missing)}")
        for raw in reader:
            try:
                run.rows.append({key: float(raw[key]) for key in REQUIRED})
            except (TypeError, ValueError):
                continue  # a broken row is skipped, not repaired into a plausible number
    return run


def summarise(run: Run) -> dict:
    """Per-run value = median over the file's windows (protocol 7.1).

    Rows without samples are dropped: a zero frame time is not a perfect frame, it is
    a missing measurement.
    """
    usable = [row for row in run.rows if row["ms_p50"] > 0]
    if not usable:
        raise ValueError(f"{run.name}: keine Fenster mit Messwerten")
    return {
        "name": run.name,
        "p95": statistics.median(row["ms_p95"] for row in usable),
        "p95_worst": max(row["ms_p95"] for row in usable),
        "low": statistics.median(row["fps_1pct_low"] for row in usable),
        "hitches": statistics.median(row["hitches"] for row in usable),
        "p50": statistics.median(row["ms_p50"] for row in usable),
        "budget_share": statistics.median(row["under_budget_pct"] for row in usable),
        "target_hz": usable[0]["target_hz"],
        "dropped": len(run.rows) - len(usable),
    }


def hitches_per_minute(group: Group) -> float:
    """One window covers `window` frames; convert the per-window count to a rate.

    Windows overlap, which is why the protocol takes the median and not a sum.
    """
    window = group.window_frames
    seconds = window * (group.median("p50") / 1000.0)
    if seconds <= 0:
        return 0.0
    return group.median("hitches") * 60.0 / seconds


def verdict(group: Group) -> str:
    """Decision rule from protocol 7.4."""
    p95 = group.median("p95")
    hitches = hitches_per_minute(group)
    if p95 <= group.budget_ms and hitches <= HITCH_LIMIT_PER_MINUTE:
        return "geeignet"
    if p95 <= group.budget_ms * BORDERLINE_FACTOR and hitches <= HITCH_LIMIT_PER_MINUTE:
        return "grenzwertig"
    return "ungeeignet"


def distinguishable(first: Group, second: Group) -> bool:
    """Protocol 7.3: only non-overlapping p95 ranges count as a shown difference."""
    low_a, high_a = first.spread("p95")
    low_b, high_b = second.spread("p95")
    return high_a < low_b or high_b < low_a


def build_groups(paths: list[Path], window: int) -> list[Group]:
    groups: dict[tuple[str, str], list[dict]] = {}
    dropped = 0
    for path in sorted(paths):
        run = read_run(path)
        summary = summarise(run)
        dropped += int(summary["dropped"])
        groups.setdefault((run.device, run.tier), []).append(summary)

    built: list[Group] = []
    for (device, tier), runs in sorted(groups.items()):
        rates = {run["target_hz"] for run in runs}
        if len(rates) != 1:
            raise ValueError(
                f"{device}/{tier}: gemischte Bildwiederholraten {sorted(rates)}. "
                "Laeufe mit unterschiedlichem Profil gehoeren nicht in eine Gruppe.")
        built.append(Group(device, tier, rates.pop(), runs, window, dropped))
    return built


def render(groups: list[Group], min_runs: int) -> str:
    lines: list[str] = []
    for device in sorted({group.device for group in groups}):
        device_groups = [group for group in groups if group.device == device]
        lines.append(f"### {device}")
        lines.append("")
        lines.append("| Stufe | Ziel | p95 ms (Median) | p95 Spannweite | 1%-Low | "
                     "Hitches/min | im Budget | Laeufe | Urteil |")
        lines.append("|---|---|---|---|---|---|---|---|---|")
        for group in sorted(device_groups, key=lambda item: item.median("p95")):
            low, high = group.spread("p95")
            lines.append(
                f"| {group.tier or '-'} | {group.target_hz:.0f} Hz "
                f"| {group.median('p95'):.2f} | {low:.2f} - {high:.2f} "
                f"| {group.median('low'):.1f} | {hitches_per_minute(group):.2f} "
                f"| {group.median('budget_share'):.1f} % | {len(group.runs)} "
                f"| **{verdict(group)}** |")
        lines.append("")
        short = [group for group in device_groups if len(group.runs) < min_runs]
        for group in short:
            lines.append(f"- Achtung: `{group.tier}` hat nur {len(group.runs)} Laeufe, "
                         f"das Protokoll verlangt {min_runs}. Die Spannweite ist damit "
                         f"keine belastbare Rauschgrenze.")
        if short:
            lines.append("")
        pairs = [(a, b) for index, a in enumerate(sorted(device_groups, key=lambda g: g.tier))
                 for b in sorted(device_groups, key=lambda g: g.tier)[index + 1:]]
        if pairs:
            lines.append("| Vergleich | p95-Bereiche | Unterschied |")
            lines.append("|---|---|---|")
            for first, second in pairs:
                low_a, high_a = first.spread("p95")
                low_b, high_b = second.spread("p95")
                shown = "gezeigt" if distinguishable(first, second) else "**nicht gezeigt**"
                lines.append(f"| {first.tier} / {second.tier} "
                             f"| {low_a:.2f}-{high_a:.2f} / {low_b:.2f}-{high_b:.2f} "
                             f"| {shown} |")
            lines.append("")
    return "\n".join(lines)


def run_self_test() -> int:
    """Synthetic data only: proves the rules, claims nothing about hardware."""
    def write(directory: Path, name: str, rows: list[tuple[float, float, float, float, float, float]]):
        path = directory / f"{name}.csv"
        with path.open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["t", "ms_avg", "ms_p50", "ms_p95", "fps_1pct_low", "hitches",
                             "under_budget_pct", "target_hz"])
            for index, (p50, p95, low, hitches, share, hz) in enumerate(rows):
                writer.writerow([index * 5.0, p50, p50, p95, low, hitches, share, hz])
        return path

    def block(p50, p95, low, hitches, share, hz, count=6):
        return [(p50, p95, low, hitches, share, hz)] * count

    failures = []
    with tempfile.TemporaryDirectory() as raw:
        directory = Path(raw)
        # Breite Streuung innerhalb eines Laufs, damit der Median etwas zu tun hat.
        write(directory, "quest3s-leistung-1", block(10.0, 11.0, 60.0, 0.0, 95.0, 72.0)
              + block(10.5, 12.0, 58.0, 0.0, 94.0, 72.0))
        write(directory, "quest3s-leistung-2", block(10.0, 11.5, 60.0, 0.0, 95.0, 72.0))
        write(directory, "quest3s-leistung-3", block(10.2, 11.8, 59.0, 0.0, 95.0, 72.0))
        # Deutlich langsamer, Bereiche ueberlappen nicht.
        write(directory, "quest3s-schaerfer-1", block(18.0, 20.0, 45.0, 3.0, 40.0, 72.0))
        write(directory, "quest3s-schaerfer-2", block(18.5, 21.0, 44.0, 4.0, 38.0, 72.0))
        write(directory, "quest3s-schaerfer-3", block(19.0, 20.5, 44.0, 3.0, 39.0, 72.0))
        # Genau im Grenzband: 15 ms bei 72 Hz ist 1,08 x Budget.
        write(directory, "quest3s-ausgewogen-1", block(14.0, 15.0, 55.0, 0.0, 80.0, 72.0))
        write(directory, "quest3s-ausgewogen-2", block(14.2, 15.2, 55.0, 0.0, 80.0, 72.0))
        write(directory, "quest3s-ausgewogen-3", block(14.1, 15.1, 55.0, 0.0, 80.0, 72.0))

        groups = build_groups(sorted(directory.glob("*.csv")), window=512)
        by_tier = {group.tier: group for group in groups}
        if len(groups) != 3:
            failures.append(f"erwartet 3 Gruppen, erhalten {len(groups)}")
        if verdict(by_tier["leistung"]) != "geeignet":
            failures.append(f"leistung: {verdict(by_tier['leistung'])} statt geeignet")
        if verdict(by_tier["ausgewogen"]) != "grenzwertig":
            failures.append(f"ausgewogen: {verdict(by_tier['ausgewogen'])} statt grenzwertig")
        if verdict(by_tier["schaerfer"]) != "ungeeignet":
            failures.append(f"schaerfer: {verdict(by_tier['schaerfer'])} statt ungeeignet")
        if distinguishable(by_tier["leistung"], by_tier["schaerfer"]) is not True:
            failures.append("klarer Abstand muss als gezeigt gelten")

        # Ueberlappende Bereiche: 11-12 gegen 11.5-12.5 darf nicht als gezeigt gelten.
        with tempfile.TemporaryDirectory() as second_raw:
            second = Path(second_raw)
            write(second, "quest3-eng-1", block(10.0, 11.0, 60.0, 0.0, 95.0, 90.0))
            write(second, "quest3-eng-2", block(10.0, 12.0, 60.0, 0.0, 95.0, 90.0))
            write(second, "quest3-weit-1", block(10.0, 11.5, 60.0, 0.0, 95.0, 90.0))
            write(second, "quest3-weit-2", block(10.0, 12.5, 60.0, 0.0, 95.0, 90.0))
            overlapping = build_groups(sorted(second.glob("*.csv")), window=512)
            overlap_by_tier = {group.tier: group for group in overlapping}
            if distinguishable(overlap_by_tier["eng"], overlap_by_tier["weit"]) is not False:
                failures.append("ueberlappende Bereiche muessen als nicht gezeigt gelten")

            # Gemischte Raten in einer Gruppe muessen abbrechen, nicht mitteln.
            write(second, "quest3-eng-3", block(10.0, 11.0, 60.0, 0.0, 95.0, 72.0))
            try:
                build_groups(sorted(second.glob("*.csv")), window=512)
            except ValueError:
                pass
            else:
                failures.append("gemischte target_hz haette abbrechen muessen")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 3
    print("PASS Auswertung: Urteile geeignet/grenzwertig/ungeeignet, Rauschgrenze bei "
          "ueberlappenden Bereichen, Abbruch bei gemischten Raten")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", nargs="*", type=Path, help="eine CSV je Lauf")
    parser.add_argument("--window", type=int, default=512,
                        help="Frames pro Fenster, muss gquest_perf_window entsprechen")
    parser.add_argument("--min-runs", type=int, default=3,
                        help="vom Protokoll verlangte Wiederholungen je Stufe")
    parser.add_argument("--test", action="store_true", help="synthetischer Selbsttest")
    arguments = parser.parse_args()

    if arguments.test:
        return run_self_test()
    if not arguments.csv:
        parser.error("keine CSV angegeben (oder --test)")

    try:
        groups = build_groups(arguments.csv, arguments.window)
    except (ValueError, OSError) as error:
        print(f"Eingabefehler: {error}")
        return 2

    print(render(groups, arguments.min_runs))
    print("Regeln: docs/PERF_PROTOCOL.md, Abschnitte 7.3 und 7.4. "
          "Grenzwerte sind Vorschlaege, keine gemessenen Fakten.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
