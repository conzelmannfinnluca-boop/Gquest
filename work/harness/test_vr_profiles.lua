-- Boundary test for the per-device VR profile module. No engine surface is needed
-- beyond file.Read/file.Write, so the whole selection logic runs unmodified.
local writes = {}
file = {
    Read = function(path) return writes[path] end,
    Write = function(path, text) writes[path] = text end,
}
dofile("work/gquest-ui/lua/autorun/client/gquest_vr_profiles.lua")
local P = GQUEST_PROFILES
assert(P, "profile module missing")

-- The runtime accepts exactly these strings; if the menu ever writes another one the
-- game silently falls back to its built-in default. Kept in sync with lib.rs TIERS.
local RUNTIME_TIERS = {
    ["1032x1104"] = true, ["1548x1656"] = true, ["1680x1760"] = true,
    ["916x960"] = true, ["1374x1440"] = true, ["1558x1632"] = true,
}

local function tierKnown(deviceId, tier)
    for _, name in ipairs(P.DEVICES[deviceId].tiers) do
        if name == tier then return true end
    end
    return false
end

-- 1) Device tables are complete and every tier is one the runtime accepts.
assert(#P.ORDER == 2 and P.ORDER[1] == "quest3" and P.ORDER[2] == "quest3s", "device order")
for _, id in ipairs(P.ORDER) do
    local device = P.DEVICES[id]
    assert(device, "missing device table: " .. id)
    assert(#device.tiers == 3, id .. ": expected three tiers")
    assert(#device.tier_labels == 3, id .. ": expected three tier labels")
    for _, tier in ipairs(device.tiers) do
        assert(RUNTIME_TIERS[tier], id .. ": tier not accepted by the runtime: " .. tier)
    end
    assert(not tierKnown(id, id == "quest3" and "1374x1440" or "1548x1656"),
        id .. ": tier sets must be device specific")
end

-- 2) Defaults mirror the Rust default so the menu never shows a profile the game
-- is not actually running.
local defaults = P.Defaults()
assert(defaults.device == "quest3", "default device")
assert(defaults.tier == P.RUNTIME_DEFAULT.tier, "default tier must match the runtime")
assert(defaults.tier == "1032x1104", "runtime default tier")
assert(defaults.foveation == 2 and defaults.rate == 72, "runtime default foveation/rate")
assert(defaults.tierIndex == 1, "default tier index")

-- 3) A legacy three-line profile written before the split still loads.
local legacy = P.Parse("1548x1656\r\n1\r\n90\r\n")
assert(legacy.device == "quest3", "legacy file must resolve to Quest 3")
assert(legacy.tier == "1548x1656" and legacy.tierIndex == 2, "legacy tier")
assert(legacy.foveation == 1 and legacy.rate == 90, "legacy foveation and rate")

-- 4) Empty and nil input produce the defaults.
for _, text in ipairs({ "", nil }) do
    local state = P.Parse(text)
    assert(state.tier == "1032x1104" and state.device == "quest3", "empty input defaults")
end

-- 5) A tier from the other device snaps to this device's performance tier rather
-- than running a resolution nobody selected.
local crossed = P.Parse("1680x1760\n2\n90\nquest3s\n")
assert(crossed.device == "quest3s", "device line")
assert(crossed.tier == "916x960", "foreign tier must snap, got " .. crossed.tier)
assert(crossed.tierIndex == 1, "foreign tier index")

-- 6) Unknown device id falls back to Quest 3; invalid numbers fall back too.
local unknown = P.Parse("916x960\n9\n120\nnonsense\n")
assert(unknown.device == "quest3", "unknown device must fall back")
assert(unknown.tier == "1032x1104", "tier must be re-validated for the fallback device")
assert(unknown.foveation == 2, "invalid foveation must fall back")
assert(unknown.rate == 72, "invalid rate must fall back")

-- 7) Remembered presets are restored, and invalid slots are ignored.
local remembered = P.Parse("1374x1440\n2\n90\nquest3s\nquest3=3,1,90\nquest3s=9,2,72\n")
assert(remembered.saved.quest3, "valid preset slot must load")
assert(remembered.saved.quest3.tier == 3 and remembered.saved.quest3.foveation == 1, "slot values")
assert(remembered.saved.quest3s == nil, "out-of-range tier must be ignored")

-- 8) Switching device remembers the current values and restores the target's.
local state = P.Defaults()
P.SetTier(state, 2); P.SetFoveation(state, 1); P.SetRate(state, 72)
P.SetDevice(state, "quest3s")
assert(state.device == "quest3s", "device not switched")
assert(state.tier == "1374x1440", "quest3s recommendation tier")
assert(state.foveation == 2 and state.rate == 72, "quest3s recommendation values")
assert(state.saved.quest3 and state.saved.quest3.tier == 2 and state.saved.quest3.foveation == 1,
    "quest3 tuning must be remembered")
P.SetTier(state, 3); P.SetFoveation(state, 0); P.SetRate(state, 90)
P.SetDevice(state, "quest3")
assert(state.tier == "1548x1656" and state.foveation == 1 and state.rate == 72,
    "switching back must restore the remembered Quest 3 tuning")
assert(state.saved.quest3s.tier == 3 and state.saved.quest3s.foveation == 0,
    "quest3s tuning must be remembered")

-- 9) Unknown device requests change nothing.
local beforeDevice, beforeTier = state.device, state.tier
P.SetDevice(state, "questpro")
assert(state.device == beforeDevice and state.tier == beforeTier, "unknown device accepted")

-- 10) Setters reject out-of-range values instead of clamping silently.
local guard = P.Defaults()
P.SetTier(guard, 0); assert(guard.tierIndex == 1, "tier 0 accepted")
P.SetTier(guard, 4); assert(guard.tierIndex == 1, "tier 4 accepted")
P.SetFoveation(guard, 5); assert(guard.foveation == 2, "foveation 5 accepted")
P.SetFoveation(guard, -1); assert(guard.foveation == 2, "negative foveation accepted")
P.SetRate(guard, 60); assert(guard.rate == 72, "60 Hz accepted")
P.SetRate(guard, 120); assert(guard.rate == 72, "120 Hz accepted")
P.SetTier(guard, 2); assert(guard.tier == "1548x1656", "tier 2 not applied")

-- 11) Recommendations are device specific.
local perDevice = P.Defaults()
P.Recommend(perDevice)
assert(perDevice.tier == "1680x1760" and perDevice.foveation == 2 and perDevice.rate == 90,
    "Quest 3 recommendation")
P.SetDevice(perDevice, "quest3s")
perDevice.saved.quest3s = nil
P.Recommend(perDevice)
assert(perDevice.tier == "1374x1440" and perDevice.rate == 72, "Quest 3S recommendation")

-- 12) File layout: the first three lines are exactly what the runtime reads.
local layoutState = P.Parse("1558x1632\n3\n90\nquest3s\nquest3=1,0,72\n")
writes = {}
assert(P.Save(layoutState), "save failed")
local savedText = writes[P.PATH]
assert(savedText, "nothing written to " .. P.PATH)
local savedLines = {}
for line in string.gmatch(savedText, "[^\r\n]+") do savedLines[#savedLines + 1] = line end
assert(savedLines[1] == "1558x1632", "line 1 must be the tier")
assert(savedLines[2] == "3", "line 2 must be the foveation level")
assert(savedLines[3] == "90", "line 3 must be the refresh rate")
assert(savedLines[4] == "quest3s", "line 4 must be the device")
assert(savedLines[5] and savedLines[5]:find("^quest3=1,0,72$"), "preset slot format")

-- 13) Save then Load is stable.
local reloaded = P.Load()
assert(reloaded.device == "quest3s" and reloaded.tier == "1558x1632", "round trip device and tier")
assert(reloaded.foveation == 3 and reloaded.rate == 90, "round trip numbers")
assert(reloaded.saved.quest3 and reloaded.saved.quest3.tier == 1, "round trip preset slot")
assert(P.Serialize(reloaded) == savedText, "serialize must be idempotent")

-- 14) The detected headset is read from the bridge hint file.
writes = {}
assert(P.Detected() == nil, "no hint file must yield nil")
writes[P.DEVICE_HINT_PATH] = "quest3s\n"
assert(P.Detected() == "quest3s", "hint file not read")
writes[P.DEVICE_HINT_PATH] = "  quest3  \r\n"
assert(P.Detected() == "quest3", "hint file must tolerate whitespace and CRLF")
writes[P.DEVICE_HINT_PATH] = "questpro\n"
assert(P.Detected() == nil, "unknown hint must be ignored")

-- 15) With nothing saved, the menu starts on the detected device and shows the same
-- recommendation the Rust policy applies, so the numbers cannot disagree.
writes = {}
writes[P.DEVICE_HINT_PATH] = "quest3s\n"
local fresh = P.Load()
assert(fresh.device == "quest3s", "fresh load must use the detected device")
assert(fresh.tier == "1374x1440" and fresh.foveation == 2 and fresh.rate == 72,
    "fresh load must use the detected device recommendation")
writes[P.DEVICE_HINT_PATH] = "quest3\n"
local freshThree = P.Load()
assert(freshThree.device == "quest3" and freshThree.tier == "1680x1760" and freshThree.rate == 90,
    "fresh Quest 3 load")

-- 16) An existing profile wins over detection: a user's choice is never overwritten.
writes = {}
writes[P.DEVICE_HINT_PATH] = "quest3\n"
writes[P.PATH] = "916x960\n3\n72\nquest3s\n"
local savedState = P.Load()
assert(savedState.device == "quest3s" and savedState.tier == "916x960",
    "saved profile must win over detection")

-- 17) An explicit id overrides the hint file; an unknown one changes nothing.
writes = {}
local explicit = P.Load("quest3s")
assert(explicit.device == "quest3s", "explicit detected id ignored")
local bogus = P.Load("questpro")
assert(bogus.device == "quest3", "unknown detected id must not switch the device")

-- 18) The menu status line reports all three detection states.
writes = {}
local noneText, noneSeverity = P.DetectionLabel(P.Defaults())
assert(noneSeverity == "none" and noneText:find("kein Geraet", 1, true),
    "no detection must say so")
writes[P.DEVICE_HINT_PATH] = "quest3s\n"
local matched = P.Defaults()
matched.device = "quest3s"
local matchText, matchSeverity = P.DetectionLabel(matched)
assert(matchSeverity == "match" and matchText:find("Quest 3S", 1, true)
    and matchText:find("passt", 1, true), "matching device must be reported")
writes[P.DEVICE_HINT_PATH] = "quest3\n"
local mismatchText, mismatchSeverity = P.DetectionLabel(matched)
assert(mismatchSeverity == "mismatch" and mismatchText:find("Quest 3 ", 1, true)
    and mismatchText:find("weicht ab", 1, true), "mismatch must be reported")
-- An explicit id wins over the hint file, so the menu can reuse the value it loaded.
assert(select(2, P.DetectionLabel(matched, "quest3s")) == "match", "explicit id ignored")

print("PASS per-device VR profiles: separate tier sets accepted by the runtime, runtime-matching "
    .. "defaults, legacy and CRLF parsing, foreign-tier snap, invalid value fallbacks, preset "
    .. "remembering across device switches, setter guards, stable round trip, detection-aware "
    .. "load and the three-state detection status line")
