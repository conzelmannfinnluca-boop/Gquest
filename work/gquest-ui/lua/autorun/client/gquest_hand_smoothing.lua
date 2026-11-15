-- Hand pose smoothing for the tracking provider.
--
-- The head is deliberately not smoothed: a lagging view is nauseating, while a lagging hand
-- reads as weight. Hands are smoothed with an exponential filter whose factor comes from the
-- frame step, so the result does not change with the frame rate.
--
-- Three rules matter more than the factor:
--   * the first sample of a hand snaps - a lag on the very first frame looks like a jump;
--   * without a usable time step the last pose is held, never extrapolated;
--   * a jump beyond TELEPORT_INCHES snaps, because a teleport is not motion and sliding there
--     would take several time constants.
--
-- Plain tables in and out (no Vector/Angle), so the harness needs no engine surface.
GquestHandSmoothing = GquestHandSmoothing or {}
GquestHandSmoothing.Enabled = true
-- 30 ms: enough to take the jitter out of the tracking, short enough to stay usable in a fight.
GquestHandSmoothing.TAU = 0.03
GquestHandSmoothing.TELEPORT_INCHES = 24
-- The menu stores a name, this table owns what the name means. Off is not a zero constant:
-- it disables the filter outright so no state is kept and nothing can drift.
GquestHandSmoothing.LEVELS = { off = 0, mild = 0.03, strong = 0.06 }

local state = {}  -- [hand] = {pos={x,y,z}, ang={p,y,r}}

local function wrapDelta(from, to)
    return (to - from + 180) % 360 - 180
end

local function factorFor(deltaSeconds)
    if type(deltaSeconds) ~= "number" or deltaSeconds ~= deltaSeconds or deltaSeconds <= 0 then
        return 0
    end
    if GquestHandSmoothing.TAU <= 0 then return 1 end
    return 1 - math.exp(-deltaSeconds / GquestHandSmoothing.TAU)
end

--- Set the smoothing from a level name. False for an unknown name, which leaves the current
--- setting untouched instead of falling back to a guess.
function GquestHandSmoothing.SetLevel(level)
    local tau = GquestHandSmoothing.LEVELS[level]
    if tau == nil then return false end
    GquestHandSmoothing.Enabled = tau > 0
    GquestHandSmoothing.TAU = tau
    -- One line when the setting is applied, so a hardware log can show which level actually
    -- reached the filter instead of only which one the profile mentions.
    print("GQUEST_HANDSMOOTH level=" .. level .. " tau=" .. string.format("%.3f", tau)
        .. " enabled=" .. tostring(GquestHandSmoothing.Enabled))
    return true
end

--- Forget one hand, or every hand when `hand` is nil. The next sample then snaps.
function GquestHandSmoothing.Reset(hand)
    if hand == nil then
        state = {}
    else
        state[hand] = nil
    end
end

--- raw = {pos={x,y,z}, ang={p,y,r}} in world space. Returns the pose to publish.
--- The returned table is owned by this module: copy it before keeping it.
function GquestHandSmoothing.Apply(hand, raw, deltaSeconds, deltaUsable)
    if type(raw) ~= "table" or type(raw.pos) ~= "table" or type(raw.ang) ~= "table" then
        return nil
    end
    local previous = state[hand]
    if not previous then
        previous = {pos = {x = raw.pos.x, y = raw.pos.y, z = raw.pos.z},
                    ang = {p = raw.ang.p, y = raw.ang.y, r = raw.ang.r}}
        state[hand] = previous
        return previous
    end
    if not GquestHandSmoothing.Enabled then
        previous.pos.x, previous.pos.y, previous.pos.z = raw.pos.x, raw.pos.y, raw.pos.z
        previous.ang.p, previous.ang.y, previous.ang.r = raw.ang.p, raw.ang.y, raw.ang.r
        return previous
    end
    -- A frame without a usable step holds what is on screen; guessing a step here would be
    -- exactly the stall the clamp exists to prevent.
    if not deltaUsable then return previous end

    local dx = raw.pos.x - previous.pos.x
    local dy = raw.pos.y - previous.pos.y
    local dz = raw.pos.z - previous.pos.z
    local alpha = factorFor(deltaSeconds)
    if dx * dx + dy * dy + dz * dz >
       GquestHandSmoothing.TELEPORT_INCHES * GquestHandSmoothing.TELEPORT_INCHES then
        alpha = 1
    end

    previous.pos.x = previous.pos.x + dx * alpha
    previous.pos.y = previous.pos.y + dy * alpha
    previous.pos.z = previous.pos.z + dz * alpha
    previous.ang.p = previous.ang.p + wrapDelta(previous.ang.p, raw.ang.p) * alpha
    previous.ang.y = previous.ang.y + wrapDelta(previous.ang.y, raw.ang.y) * alpha
    previous.ang.r = previous.ang.r + wrapDelta(previous.ang.r, raw.ang.r) * alpha
    return previous
end
