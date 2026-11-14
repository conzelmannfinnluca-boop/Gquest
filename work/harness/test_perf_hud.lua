-- Boundary test for the performance sampler. Engine surface is mocked; the module
-- itself runs unmodified. Checks the statistics that the frame-rate claim depends on.
local hooks, commands, writes, changeCallbacks = {}, {}, {}, {}
local now, frameTime = 0, 0
local convarValues = {
    gquest_perf_enabled = "1", gquest_perf_csv = "1",
    gquest_perf_interval = "5", gquest_perf_window = "512",
}
local drawn, drawnText = 0, 0

function CreateClientConVar(name)
    return {
        GetBool = function() return convarValues[name] == "1" end,
        GetString = function() return convarValues[name] end,
    }
end
file = {
    Read = function(path) return writes[path] and writes[path].value or nil end,
    Write = function(path, text) writes[path] = { value = text } end,
}
hook = { Add = function(event, _, fn) hooks[event] = fn end }
concommand = { Add = function(name, fn) commands[name] = fn end }
cvars = { AddChangeCallback = function(name, fn) changeCallbacks[name] = fn end }
function RealTime() return now end
function RealFrameTime() return frameTime end
function RunConsoleCommand(name, value) convarValues[name] = tostring(value) end
function IsValid(x) return type(x) == "table" end
function LocalPlayer() return { Ping = function() return 42 end } end
engine = { TickInterval = function() return 1 / 66 end }
ents = { GetAll = function() return { 1, 2, 3 } end }
function ScrW() return 1032 end
function ScrH() return 1104 end
surface = {
    SetFont = function() end,
    GetTextSize = function(text) return #text * 6 end,
    SetDrawColor = function() drawn = drawn + 1 end,
    DrawRect = function() drawn = drawn + 1 end,
}
draw = { SimpleText = function() drawnText = drawnText + 1 end }
function Color(r, g, b, a) return { r, g, b, a } end

dofile("work/gquest-ui/lua/autorun/client/gquest_perf_hud.lua")
local P = GQUEST_PERF
assert(P, "module table missing")

local function near(actual, expected, tolerance, label)
    assert(type(actual) == "number", label .. ": not a number: " .. tostring(actual))
    assert(actual == actual, label .. ": nan")
    assert(math.abs(actual - expected) <= (tolerance or 1e-6),
        string.format("%s: expected %.6f, got %.6f", label, expected, actual))
end

-- 1) Commands and hooks are registered.
for _, name in ipairs({
    "gquest_perf", "gquest_perf_reset", "gquest_perf_report", "gquest_perf_csv",
}) do
    assert(commands[name], "command not registered: " .. name)
end
for _, event in ipairs({ "PreRender", "Think", "HUDPaint", "ShutDown" }) do
    assert(hooks[event], "hook not registered: " .. event)
end
assert(P.CSV_HEADER:find("fps_1pct_low"), "header must name the 1% low column")

-- 2) Empty window reports zeros rather than dividing by zero.
local empty = P.Stats()
assert(empty.n == 0 and empty.fps == 0 and empty.ms_avg == 0, "empty window must be zeroed")
near(empty.budget_ms, 1000 / 72, 1e-9, "default budget from 72 Hz profile")

-- 3) Steady frames comfortably inside the 72 Hz budget (12.5 ms vs 13.89 ms).
-- Deliberately not exactly at the budget: equality there depends on float rounding,
-- and this test is about the statistics, not about ulp behaviour.
local period = 1 / 80
for _ = 1, 100 do assert(P.Sample(period)) end
local steady = P.Stats()
assert(steady.n == 100, "sample count")
near(steady.fps, 80, 1e-6, "steady fps")
near(steady.ms_avg, 12.5, 1e-6, "steady average ms")
near(steady.ms_max, 12.5, 1e-6, "steady max ms")
assert(steady.hitches == 0, "steady frames must not be hitches")
near(steady.under_budget_pct, 100, 1e-9, "steady frames all within budget")

-- 4) One long frame is a hitch and moves the maximum, not the median much.
assert(P.Sample(0.040))
local spiked = P.Stats()
near(spiked.ms_max, 40, 1e-6, "max after a 40 ms frame")
assert(spiked.hitches == 1, "a 40 ms frame must count as one hitch")
assert(spiked.under_budget_pct < 100, "a 40 ms frame is outside the 72 Hz budget")

-- 5) 1% low uses the slowest frames: 99 x 10 ms plus 1 x 100 ms.
P.Reset()
for _ = 1, 99 do P.Sample(0.010) end
P.Sample(0.100)
local mixed = P.Stats()
near(mixed.fps, 1000 / 10.9, 1e-6, "average fps over the mixed window")
near(mixed.fps_1pct_low, 10, 1e-6, "1% low is the single slowest frame")

-- 6) Invalid input is rejected instead of corrupting the window.
P.Reset()
local before = P.Count()
assert(P.Sample(0) == false, "zero frame time accepted")
assert(P.Sample(-0.01) == false, "negative frame time accepted")
assert(P.Sample(0 / 0) == false, "nan frame time accepted")
assert(P.Sample(1 / 0) == false, "inf frame time accepted")
assert(P.Sample(30) == false, "30 s stall accepted as a frame time")
assert(P.Count() == before, "rejected samples must not be stored")

-- 7) Sampling stops when the sampler is disabled.
convarValues.gquest_perf_enabled = "0"
assert(P.Sample(period) == false, "sampled while disabled")
assert(P.Count() == before, "disabled sampler stored a sample")
convarValues.gquest_perf_enabled = "1"

-- 8) The window is clamped to its documented bounds.
convarValues.gquest_perf_window = "10"
changeCallbacks.gquest_perf_window()
assert(P.Capacity() == 32, "below-minimum window must clamp to 32")
convarValues.gquest_perf_window = "99999"
changeCallbacks.gquest_perf_window()
assert(P.Capacity() == 4096, "above-maximum window must clamp to 4096")

-- 9) A smaller window keeps only the newest frames, oldest dropped.
convarValues.gquest_perf_window = "32"
changeCallbacks.gquest_perf_window()
assert(P.Capacity() == 32, "window capacity not applied")
for index = 1, 40 do P.Sample(index / 1000) end
assert(P.Count() == 32, "window overran its capacity")
local kept = P.Samples()
assert(#kept == 32, "sample list length")
near(kept[1], 9, 1e-6, "oldest kept sample is frame 9")
near(kept[32], 40, 1e-6, "newest kept sample is frame 40")

-- 9) CSV contains a header once, then one well-formed row per interval.
writes["gquest/gquest/perf.csv"] = nil
now = 0
hooks.Think()
assert(not writes["gquest/perf.csv"], "wrote a row before the interval elapsed")
now = 5
hooks.Think()
local firstCsv = writes["gquest/perf.csv"].value
assert(firstCsv:find(P.CSV_HEADER, 1, true) == 1, "CSV must start with the header")
local csvLines = {}
for line in string.gmatch(firstCsv, "[^\n]+") do csvLines[#csvLines + 1] = line end
assert(#csvLines == 2, "expected header + one row, got " .. #csvLines .. " lines")
assert(csvLines[1] == P.CSV_HEADER, "first line must be the exact header")
local _, commas = string.gsub(csvLines[2], ",", "")
assert(commas == 16, "row must have 17 columns, saw " .. commas .. " separators")
assert(not firstCsv:lower():find("nan"), "CSV contains nan")
assert(not firstCsv:lower():find("inf"), "CSV contains inf")
now = 10
hooks.Think()
local secondCsv = writes["gquest/perf.csv"].value
local headerCount = 0
for _ in string.gmatch(secondCsv, P.CSV_HEADER) do headerCount = headerCount + 1 end
assert(headerCount == 1, "header repeated on the second row")

-- 10) CSV can be switched off.
convarValues.gquest_perf_csv = "0"
local frozen = writes["gquest/perf.csv"].value
now = 20
hooks.Think()
assert(writes["gquest/perf.csv"].value == frozen, "row written while CSV disabled")
convarValues.gquest_perf_csv = "1"

-- 11) Summary is readable, finite and written on demand.
local lines = P.ReportLines()
assert(#lines == 4, "report must have four lines")
for _, line in ipairs(lines) do
    assert(not line:lower():find("nan"), "summary line contains nan")
    assert(not line:lower():find("inf"), "summary line contains inf")
end
assert(lines[4]:find("nicht messbar"), "must state that draw calls are unmeasurable")
local summaryPath = P.WriteSummary()
assert(summaryPath == "gquest/perf_summary.txt", "summary path")
assert(writes[summaryPath].value:find("GQuest Performance Summary"), "summary header")
assert(writes[summaryPath].value:find("FPS avg"), "summary must contain the fps line")

-- 12) The overlay draws only while enabled and reports the measured numbers.
drawn, drawnText = 0, 0
hooks.HUDPaint()
assert(drawn >= 2 and drawnText == 4, "overlay did not draw four lines")
drawn, drawnText = 0, 0
convarValues.gquest_perf_enabled = "0"
hooks.HUDPaint()
assert(drawn == 0 and drawnText == 0, "overlay drew while disabled")
convarValues.gquest_perf_enabled = "1"

-- 13) Shutdown writes a summary, and an empty run does not.
writes["gquest/perf_summary.txt"] = nil
hooks.ShutDown()
assert(writes["gquest/perf_summary.txt"], "shutdown must persist the summary")
P.Reset()
writes["gquest/perf_summary.txt"] = nil
hooks.ShutDown()
assert(not writes["gquest/perf_summary.txt"], "empty run must not write a summary")

print("PASS performance sampler: steady frame rate, hitch detection, 1% low, window clamp and rollover, "
    .. "invalid/nan/inf rejection, disable gate, CSV shape and header-once, summary and overlay gates")
