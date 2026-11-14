-- Per-device VR profiles.
--
-- Quest 3 and Quest 3S do not share a native panel: Quest 3 is 2064x2208 per eye,
-- Quest 3S is 1832x1920. A resolution tier that is comfortable on one is therefore
-- a different load on the other, so each device gets its own tier set and remembers
-- its own last choice.
--
-- File layout (data/gquest_vr_profile.txt):
--   line 1  eye resolution tier   read by the Rust runtime
--   line 2  foveation level 0..3  read by the Rust runtime
--   line 3  refresh rate 72|90    read by the Rust runtime
--   line 4  device id             menu bookkeeping, ignored by the runtime
--   line 5+ remembered preset per device: quest3=<tier>,<foveation>,<rate>
--
-- The runtime reads only the first three lines, so a profile written before this
-- split keeps working and an older build ignores the extra lines instead of failing.
--
-- This module holds no UI and issues no console commands: it parses, resolves and
-- serialises. The menu and the tests both use it.

GQUEST_PROFILES = GQUEST_PROFILES or {}
local P = GQUEST_PROFILES

P.PATH = "gquest_vr_profile.txt"
P.ORDER = { "quest3", "quest3s" }

-- Must match the Rust default in Gquest-Hybrid/src/lib.rs: a profile file that does
-- not exist yet has to show the values the game is actually running with.
P.RUNTIME_DEFAULT = { tier = "1032x1104", foveation = 2, rate = 72 }

P.DEVICES = {
    quest3 = {
        label = "Quest 3",
        tier_labels = { "Leistung", "Ausgewogen", "Schaerfer" },
        tiers = { "1032x1104", "1548x1656", "1680x1760" },
        recommend = { tier = 3, foveation = 2, rate = 90 },
    },
    quest3s = {
        label = "Quest 3S",
        tier_labels = { "Leistung", "Ausgewogen", "Schaerfer" },
        tiers = { "916x960", "1374x1440", "1558x1632" },
        -- Quest 3S is the performance-first device: balanced panel load at 72 Hz.
        recommend = { tier = 2, foveation = 2, rate = 72 },
    },
}

local function isRate(value)
    return value == 72 or value == 90
end

local function isFoveation(value)
    return type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 3
end

local function tierIndex(deviceId, tier)
    local device = P.DEVICES[deviceId]
    if not device then return nil end
    for index, name in ipairs(device.tiers) do
        if name == tier then return index end
    end
    return nil
end

--- Fresh state. Mirrors the runtime default so the menu never shows a profile the
--- game is not using.
function P.Defaults()
    local deviceId = P.ORDER[1]
    local device = P.DEVICES[deviceId]
    return {
        device = deviceId,
        tier = P.RUNTIME_DEFAULT.tier,
        tierIndex = tierIndex(deviceId, P.RUNTIME_DEFAULT.tier) or 1,
        foveation = P.RUNTIME_DEFAULT.foveation,
        rate = P.RUNTIME_DEFAULT.rate,
        saved = {},
        deviceTiers = device.tiers,
    }
end

function P.Parse(text)
    local state = P.Defaults()
    if type(text) ~= "string" or text == "" then return state end
    local lines = {}
    for line in string.gmatch(text, "[^\r\n]+") do lines[#lines + 1] = line end

    -- The device decides which tiers are legal, so it is resolved first.
    if lines[4] and P.DEVICES[lines[4]] then state.device = lines[4] end
    local device = P.DEVICES[state.device]

    if lines[1] then
        -- A tier from the other device, or garbage, snaps to this device's
        -- performance tier instead of running at a resolution nobody chose.
        local index = tierIndex(state.device, lines[1])
        state.tier = index and lines[1] or device.tiers[1]
    end
    state.foveation = tonumber(lines[2]) or state.foveation
    if not isFoveation(state.foveation) then state.foveation = P.RUNTIME_DEFAULT.foveation end
    state.rate = tonumber(lines[3]) or state.rate
    if not isRate(state.rate) then state.rate = P.RUNTIME_DEFAULT.rate end
    state.tierIndex = tierIndex(state.device, state.tier) or 1
    state.tier = device.tiers[state.tierIndex]
    state.deviceTiers = device.tiers

    for index = 5, #lines do
        local id, tier, foveation, rate = string.match(lines[index], "^([%w]+)=(%d+),(%d+),(%d+)$")
        if id and P.DEVICES[id] then
            local parsedTier, parsedFoveation, parsedRate = tonumber(tier), tonumber(foveation), tonumber(rate)
            local validTier = parsedTier and parsedTier >= 1 and parsedTier <= #P.DEVICES[id].tiers
            if validTier and isFoveation(parsedFoveation) and isRate(parsedRate) then
                state.saved[id] = { tier = parsedTier, foveation = parsedFoveation, rate = parsedRate }
            end
        end
    end
    return state
end

function P.Serialize(state)
    local lines = { state.tier, tostring(state.foveation), tostring(state.rate), state.device }
    for _, id in ipairs(P.ORDER) do
        local saved = state.saved[id]
        if saved then
            lines[#lines + 1] = string.format("%s=%d,%d,%d", id, saved.tier, saved.foveation, saved.rate)
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

P.DEVICE_HINT_PATH = "gquest_device.txt"

--- The headset the native bridge identified at startup, if any. Written by the
--- bridge from android.os.Build.MODEL; absent when the build cannot read it.
function P.Detected()
    local text = file.Read and file.Read(P.DEVICE_HINT_PATH, "DATA") or nil
    if type(text) ~= "string" then return nil end
    local id = string.match(text, "^%s*([%w]+)")
    if id and P.DEVICES[id] then return id end
    return nil
end

--- One line for the VR menu: did the automatic detection agree with the selection?
--- Returns the text plus a severity ("match", "mismatch", "none") for the colour.
function P.DetectionLabel(state, detectedId)
    local detected = detectedId or P.Detected()
    local device = detected and P.DEVICES[detected] or nil
    if not device then
        return "Automatisch erkannt: kein Geraet - Auswahl bleibt manuell", "none"
    end
    if state and state.device == detected then
        return "Automatisch erkannt: " .. device.label .. " - passt zur Auswahl", "match"
    end
    return "Automatisch erkannt: " .. device.label .. " - Auswahl weicht ab", "mismatch"
end

function P.Load(detectedId)
    local text = file.Read and file.Read(P.PATH, "DATA") or nil
    local state = P.Parse(text)
    if type(text) ~= "string" or text == "" then
        -- Nothing saved yet: start on the headset that is actually in use, so the
        -- numbers shown here are the ones the runtime picked (same recommendation).
        -- SetDevice is deliberately not used: it stores the current values first and
        -- would restore them unchanged when the detected device is already selected.
        local detected = detectedId or P.Detected()
        if detected and P.DEVICES[detected] then
            state.device = detected
            state.deviceTiers = P.DEVICES[detected].tiers
            state.saved = {}
            P.Recommend(state)
        end
    end
    return state
end

function P.Save(state)
    if not (file.Write and state) then return false end
    file.Write(P.PATH, P.Serialize(state))
    return true
end

--- Store the active values in the current device's slot before leaving it, so
--- switching back and forth never silently discards a tuned profile.
function P.SetDevice(state, deviceId)
    if not P.DEVICES[deviceId] then return state end
    if state.device and P.DEVICES[state.device] then
        state.saved[state.device] = {
            tier = state.tierIndex or 1,
            foveation = state.foveation,
            rate = state.rate,
        }
    end
    state.device = deviceId
    local device = P.DEVICES[deviceId]
    local restored = state.saved[deviceId] or device.recommend
    local index = restored.tier
    if not index or index < 1 or index > #device.tiers then index = 1 end
    state.tierIndex = index
    state.tier = device.tiers[index]
    state.foveation = isFoveation(restored.foveation) and restored.foveation or 2
    state.rate = isRate(restored.rate) and restored.rate or 72
    state.deviceTiers = device.tiers
    return state
end

function P.SetTier(state, index)
    local device = P.DEVICES[state.device]
    if not device then return state end
    if type(index) ~= "number" or index < 1 or index > #device.tiers then return state end
    state.tierIndex = math.floor(index)
    state.tier = device.tiers[state.tierIndex]
    return state
end

function P.SetFoveation(state, value)
    if isFoveation(value) then state.foveation = value end
    return state
end

function P.SetRate(state, value)
    if isRate(value) then state.rate = value end
    return state
end

--- Apply the selected device's recommendation to the active values.
function P.Recommend(state)
    local device = P.DEVICES[state.device]
    if not device then return state end
    local recommend = device.recommend
    P.SetTier(state, recommend.tier)
    P.SetFoveation(state, recommend.foveation)
    P.SetRate(state, recommend.rate)
    return state
end

print("GQUEST_PROFILES ready: per-device tiers for Quest 3 and Quest 3S")
