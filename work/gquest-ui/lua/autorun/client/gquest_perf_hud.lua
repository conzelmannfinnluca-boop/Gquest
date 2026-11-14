-- Gquest performance sampler and HUD.
--
-- Purpose: make the frame rate measurable instead of claimed. Sampling is separate
-- from drawing on purpose: a 2D HUD is not guaranteed to be visible inside the VR
-- view, so the CSV is the measurement of record. Sampling and CSV keep working with
-- the overlay switched off.
--
-- Measured: real frame times (RealFrameTime), the configured headset refresh from
-- gquest_vr_profile.txt, tick rate, entity count, Lua memory and ping.
-- NOT measured: draw calls and triangle counts. GMod's Lua API exposes neither
-- reliably, so this HUD reports nothing instead of inventing numbers.
--
-- Commands
--   gquest_perf 0|1            sampling + overlay on/off
--   gquest_perf_report         print the window summary, write gquest/perf_summary.txt
--   gquest_perf_reset          drop all samples
--   gquest_perf_csv 0|1        append a row per interval to gquest/perf.csv
--   gquest_perf_interval sec   seconds between CSV rows (1..60, default 5)
--   gquest_perf_window n       frames in the rolling window (32..4096, default 512)
--
-- Output on the Quest (pull with adb):
--   /sdcard/Android/data/com.gmodvr.qvrx/files/user/garrysmod/data/gquest/perf.csv
--   /sdcard/Android/data/com.gmodvr.qvrx/files/user/garrysmod/data/gquest/perf_summary.txt
--
-- CSV columns (header is written once):
--   t,fps_avg,fps_1pct_low,ms_avg,ms_p50,ms_p95,ms_p99,ms_max,hitches,under_budget_pct,
--   tick_hz,entities,lua_kb,ping_ms,width,height,target_hz

GQUEST_PERF = GQUEST_PERF or {}
local P = GQUEST_PERF

local CSV_PATH = "gquest/perf.csv"
local SUMMARY_PATH = "gquest/perf_summary.txt"
local PROFILE_PATH = "gquest_vr_profile.txt"
local DEFAULT_WINDOW = 512
local MIN_WINDOW, MAX_WINDOW = 32, 4096
local MIN_INTERVAL, MAX_INTERVAL = 1, 60
local MAX_SAMPLE_SECONDS = 5 -- anything longer is a stall, not a frame time

P.CSV_HEADER = "t,fps_avg,fps_1pct_low,ms_avg,ms_p50,ms_p95,ms_p99,ms_max,hitches,"
    .. "under_budget_pct,tick_hz,entities,lua_kb,ping_ms,width,height,target_hz"

local samples = {}      -- ring buffer, frame times in milliseconds
local capacity = 0      -- fixed until the next reset; the ring depends on it
local sampleCount = 0   -- valid entries in the ring
local sampleHead = 0    -- next write position
local totalFrames = 0
local lastCsvAt = 0
local csvWroteHeader = false
local overlayLines, overlayLinesAt = nil, 0

local enabledVar = CreateClientConVar("gquest_perf_enabled", "1", true, false,
    "Performance sampler and overlay")
local csvVar = CreateClientConVar("gquest_perf_csv", "1", true, false,
    "Append a performance row per interval to gquest/perf.csv")
local intervalVar = CreateClientConVar("gquest_perf_interval", "5", true, false,
    "Seconds between CSV rows")
local windowVar = CreateClientConVar("gquest_perf_window", tostring(DEFAULT_WINDOW), true, false,
    "Frames in the rolling window")

--- Accept only values a measurement can actually be.
local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

--- Format-safe number: anything unusable becomes the fallback, so the CSV can
--- never contain nan or inf.
local function num(value, fallback)
    return finite(value) and value or fallback
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

--- Refresh rate the headset is actually configured for, so the budget is real.
local function targetRefresh()
    local saved = file.Read and file.Read(PROFILE_PATH, "DATA")
    if type(saved) ~= "string" then return 72 end
    local index = 0
    for line in string.gmatch(saved, "[^\r\n]+") do
        index = index + 1
        if index == 3 then return tonumber(line) == 90 and 90 or 72 end
    end
    return 72
end

local function requestedWindow()
    local value = windowVar and tonumber(windowVar:GetString()) or DEFAULT_WINDOW
    if not finite(value) then value = DEFAULT_WINDOW end
    return clamp(math.floor(value), MIN_WINDOW, MAX_WINDOW)
end

local function csvInterval()
    local value = intervalVar and tonumber(intervalVar:GetString()) or 5
    if not finite(value) then value = 5 end
    return clamp(value, MIN_INTERVAL, MAX_INTERVAL)
end

function P.Reset()
    capacity = requestedWindow()
    samples = {}
    sampleCount, sampleHead = 0, 0
    totalFrames = 0
    overlayLines = nil
    print("GQUEST_PERF reset window=" .. tostring(capacity))
end

--- Store one frame time. Invalid, zero, negative or absurd values are dropped
--- instead of skewing the statistics.
function P.Sample(seconds)
    if not enabledVar or not enabledVar:GetBool() then return false end
    if not finite(seconds) or seconds <= 0 or seconds > MAX_SAMPLE_SECONDS then return false end
    if capacity <= 0 then capacity = requestedWindow() end
    samples[sampleHead] = seconds * 1000
    sampleHead = (sampleHead + 1) % capacity
    if sampleCount < capacity then sampleCount = sampleCount + 1 end
    totalFrames = totalFrames + 1
    overlayLines = nil
    return true
end

--- Raw samples, oldest first. Used by the report and by the tests.
function P.Samples()
    local ordered = {}
    if capacity <= 0 then return ordered end
    local start = (sampleHead - sampleCount) % capacity
    for index = 0, sampleCount - 1 do
        local value = samples[(start + index) % capacity]
        if value then ordered[#ordered + 1] = value end
    end
    return ordered
end

function P.Count()
    return sampleCount
end

function P.Capacity()
    return capacity
end

--- Linear-interpolated percentile over an ascending-sorted array.
local function percentile(sorted, fraction)
    local n = #sorted
    if n == 0 then return 0 end
    if n == 1 then return sorted[1] end
    local position = fraction * (n - 1) + 1
    local low = math.floor(position)
    local high = math.min(low + 1, n)
    local weight = position - low
    return sorted[low] * (1 - weight) + sorted[high] * weight
end

--- Window statistics. Always finite; n == 0 means "no data" and every rate is 0
--- rather than a division by zero.
function P.Stats()
    local raw = P.Samples()
    local n = #raw
    local refresh = targetRefresh()
    local budget = 1000 / refresh
    local result = {
        n = n, target_hz = refresh, budget_ms = budget,
        fps = 0, fps_1pct_low = 0, ms_avg = 0, ms_p50 = 0,
        ms_p95 = 0, ms_p99 = 0, ms_max = 0, hitches = 0,
        under_budget_pct = 0, total_frames = totalFrames,
    }
    if n == 0 then return result end

    local sorted = {}
    local sum = 0
    for index = 1, n do
        sorted[index] = raw[index]
        sum = sum + raw[index]
    end
    table.sort(sorted)

    result.ms_avg = sum / n
    result.ms_p50 = percentile(sorted, 0.5)
    result.ms_p95 = percentile(sorted, 0.95)
    result.ms_p99 = percentile(sorted, 0.99)
    result.ms_max = sorted[n]
    result.fps = result.ms_avg > 0 and 1000 / result.ms_avg or 0

    -- 1% low: mean of the slowest 1% of frames, at least one frame.
    local slowCount = math.max(1, math.ceil(n * 0.01))
    local slowSum = 0
    for index = n - slowCount + 1, n do slowSum = slowSum + sorted[index] end
    local slowAverage = slowSum / slowCount
    result.fps_1pct_low = slowAverage > 0 and 1000 / slowAverage or 0

    -- A hitch is a frame clearly outside the distribution. Merely missing the budget
    -- is not a hitch; that is what under_budget_pct reports.
    local hitchThreshold = math.max(result.ms_p50 * 2, budget * 1.5)
    local hitches, withinBudget = 0, 0
    for index = 1, n do
        if raw[index] > hitchThreshold then hitches = hitches + 1 end
        if raw[index] <= budget then withinBudget = withinBudget + 1 end
    end
    result.hitches = hitches
    result.under_budget_pct = withinBudget / n * 100

    for key, value in pairs(result) do
        if type(value) == "number" and not finite(value) then result[key] = 0 end
    end
    return result
end

local function environment()
    local tick = 0
    if engine and engine.TickInterval then
        local interval = engine.TickInterval()
        if finite(interval) and interval > 0 then tick = 1 / interval end
    end
    local entities = 0
    if ents and ents.GetAll then entities = #ents.GetAll() end
    local luaKb = 0
    local ok, memory = pcall(collectgarbage, "count")
    if ok and finite(memory) then luaKb = memory end
    local ping = 0
    local player = LocalPlayer and LocalPlayer()
    if IsValid(player) and player.Ping then ping = num(player:Ping(), 0) end
    return tick, entities, luaKb, ping
end

local function resolution()
    return num(ScrW and ScrW(), 0), num(ScrH and ScrH(), 0)
end

local function formatRow()
    local stats = P.Stats()
    local tick, entities, luaKb, ping = environment()
    local width, height = resolution()
    return string.format(
        "%.3f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.2f,%.2f,%d,%.1f,%.1f,%d,%d,%d",
        num(RealTime and RealTime(), 0),
        stats.fps, stats.fps_1pct_low, stats.ms_avg, stats.ms_p50, stats.ms_p95,
        stats.ms_p99, stats.ms_max, stats.hitches, stats.under_budget_pct,
        tick, entities, luaKb, ping, width, height, stats.target_hz)
end

local function appendCsv()
    if not csvVar or not csvVar:GetBool() then return end
    if P.Count() == 0 then return end
    local existing = file.Read and file.Read(CSV_PATH, "DATA")
    local payload = type(existing) == "string" and existing or ""
    if not csvWroteHeader then
        if payload == "" then payload = P.CSV_HEADER .. "\n" end
        csvWroteHeader = true
    end
    file.Write(CSV_PATH, payload .. formatRow() .. "\n")
end

--- Human-readable summary, shared by the console output, the overlay and the file.
function P.ReportLines()
    local stats = P.Stats()
    local tick, entities, luaKb, ping = environment()
    local width, height = resolution()
    return {
        string.format("Ziel %d Hz (Budget %.1f ms), Fenster %d Frames, gesamt %d",
            stats.target_hz, stats.budget_ms, stats.n, stats.total_frames),
        string.format("FPS avg %.1f | 1%% low %.1f | avg %.2f ms | P50 %.2f P95 %.2f P99 %.2f max %.2f",
            stats.fps, stats.fps_1pct_low, stats.ms_avg, stats.ms_p50,
            stats.ms_p95, stats.ms_p99, stats.ms_max),
        string.format("Hitches %d | im Budget %.1f%% | Tick %.1f Hz | Entities %d | Lua %.1f MB | Ping %.0f ms | %dx%d",
            stats.hitches, stats.under_budget_pct, tick, entities, luaKb / 1024, ping, width, height),
        "Zeichenaufrufe/Dreiecke: nicht messbar (GMod-Lua stellt sie nicht bereit)",
    }
end

function P.WriteSummary()
    local stamp = os and os.date and os.date("%Y-%m-%d %H:%M:%S") or "unbekannte Zeit"
    file.Write(SUMMARY_PATH, "GQuest Performance Summary | " .. stamp .. "\n"
        .. table.concat(P.ReportLines(), "\n") .. "\n")
    return SUMMARY_PATH
end

concommand.Add("gquest_perf", function(_, _, args)
    local requested = tonumber(args and args[1] or "")
    local enable
    if requested == nil then
        enable = not (enabledVar and enabledVar:GetBool())
    else
        enable = requested ~= 0
    end
    RunConsoleCommand("gquest_perf_enabled", enable and "1" or "0")
    print("GQUEST_PERF sampling=" .. tostring(enable))
end)

concommand.Add("gquest_perf_reset", function() P.Reset() end)

concommand.Add("gquest_perf_report", function()
    for _, line in ipairs(P.ReportLines()) do print("GQUEST_PERF " .. line) end
    print("GQUEST_PERF summary=" .. P.WriteSummary())
end)

concommand.Add("gquest_perf_csv", function(_, _, args)
    local requested = tonumber(args and args[1] or "")
    local enable = requested == nil and not (csvVar and csvVar:GetBool()) or (requested or 0) ~= 0
    RunConsoleCommand("gquest_perf_csv", enable and "1" or "0")
    print("GQUEST_PERF csv=" .. tostring(enable))
end)

-- The ring depends on its capacity, so changing the window starts a new window.
if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("gquest_perf_window", function() P.Reset() end)
end

-- Per rendered frame. Sampling lives here, not in the draw hook, so numbers stay
-- valid while the overlay is hidden.
hook.Add("PreRender", "GquestPerfSample", function()
    P.Sample(RealFrameTime and RealFrameTime() or 0)
end)

hook.Add("Think", "GquestPerfCsv", function()
    local now = num(RealTime and RealTime(), 0)
    if now - lastCsvAt < csvInterval() then return end
    lastCsvAt = now
    appendCsv()
end)

hook.Add("HUDPaint", "GquestPerfOverlay", function()
    if not (enabledVar and enabledVar:GetBool()) then return end
    local now = num(RealTime and RealTime(), 0)
    if not overlayLines or now - overlayLinesAt >= 0.25 then
        overlayLines = P.ReportLines()
        overlayLinesAt = now
    end
    local lines = overlayLines
    surface.SetFont("DermaDefault")
    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, num(surface.GetTextSize(line), 0))
    end
    surface.SetDrawColor(0, 0, 0, 170)
    surface.DrawRect(24, 24, width + 20, #lines * 18 + 16)
    for index, line in ipairs(lines) do
        draw.SimpleText(line, "DermaDefault", 34, 32 + (index - 1) * 18,
            Color(120, 200, 255, 255))
    end
end)

hook.Add("ShutDown", "GquestPerfSummary", function()
    if P.Count() > 0 then P.WriteSummary() end
end)

P.Reset()
print("GQUEST_PERF ready: sampler + optional overlay; gquest_perf / gquest_perf_report")
