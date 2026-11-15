"""Per-frame code must not integrate raw frame time.

Finding, 15 November 2026: the weapon and hand paths have no smoothing at all. `FrameTime`
and `RealFrameTime` appear exactly once in the shipped Lua, in the performance sampler, and
there clamping the value would falsify the measurement rather than protect it. So there was
nothing to hand the core's clamped step to.

This check keeps it that way: whoever writes the first smoothing in a weapon or hand path
cannot reach for `FrameTime()` unnoticed. The step has to come from `FrameTimer` in
`core/platform/gquest_iclock.h`, which holds an unusable sample instead of integrating it.

Exit 0 when the policy holds, 1 when it does not, 2 when the tree is missing.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent.parent
LUA_ROOT = BASE / "work/gquest-ui/lua"

# The sampler measures frame times; that is its job, and clamping would turn a measured hitch
# into a smaller number. It is the one place the raw reading is correct.
ALLOWED_FILES = {"gquest_perf_hud.lua"}

CALL = re.compile(r"\b(FrameTime|RealFrameTime)\s*\(")


def strip_comment(line: str) -> str:
    """Drop a Lua line comment. Naive about `--` inside a string, which no shipped file has."""
    return line.split("--", 1)[0]


def scan_text(name: str, text: str) -> list[tuple[int, str]]:
    """Return (line, call) for every raw frame time use that the policy forbids."""
    if name in ALLOWED_FILES:
        return []
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        for match in CALL.finditer(strip_comment(line)):
            found.append((number, match.group(1)))
    return found


def scan_tree(root: Path) -> list[tuple[str, int, str]]:
    violations = []
    for path in sorted(root.rglob("*.lua")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for number, call in scan_text(path.name, text):
            violations.append((str(path.relative_to(BASE)), number, call))
    return violations


def self_test() -> list[str]:
    """Check the scanner itself, so a green run means something."""
    problems: list[str] = []

    def expect(name: str, text: str, count: int) -> None:
        found = scan_text(name, text)
        if len(found) != count:
            problems.append(f"{name}: expected {count} finding(s), got {len(found)} for {text!r}")

    expect("gquest_weapon_align.lua", "local dt = FrameTime()", 1)
    expect("gquest_weapon_align.lua", "local dt = RealFrameTime()", 1)
    expect("gquest_native_weapon_pose.lua", "if FrameTime() > 0 then end", 1)
    expect("gquest_weapon_align.lua", "-- FrameTime() only in a comment", 0)
    expect("gquest_perf_hud.lua", "P.Sample(RealFrameTime and RealFrameTime() or 0)", 0)
    return problems


def main(argv: list[str]) -> int:
    if not LUA_ROOT.is_dir():
        print(f"missing Lua tree: {LUA_ROOT}", file=sys.stderr)
        return 2
    violations = scan_tree(LUA_ROOT)
    for path, line, call in violations:
        print(f"VIOLATION {path}:{line} uses {call}() outside the sampler")
    if "--test" in argv:
        problems = self_test()
        for problem in problems:
            print(f"FAIL {problem}")
        if problems or violations:
            return 1
        print(
            "PASS frame time policy: raw FrameTime is allowed only in the performance "
            "sampler, which measures instead of integrating; weapon and hand code has to "
            "take the clamped step from FrameTimer"
        )
        return 0
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
