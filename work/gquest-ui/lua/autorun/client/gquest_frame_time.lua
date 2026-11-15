-- The overlay's frame step, clamped the same way as FrameTimer in core/platform/gquest_iclock.h.
--
-- Nothing in this file smooths anything; it only decides how much time passed and whether
-- that number may be used. A frozen or backwards clock, or a reading that is not a number,
-- holds the previous step instead of being integrated, and the timer resyncs so one glitch
-- does not make every following frame look backwards too.
--
-- Callers pass the reading in, so a harness can drive time without a clock.
GquestFrameTime = GquestFrameTime or {}
GquestFrameTime.MAX_SECONDS = 0.5

local last, kept = nil, 0

--- Returns delta, usable.
function GquestFrameTime.Step(now)
    if type(now) ~= "number" or now ~= now then return kept, false end
    if now == math.huge or now == -math.huge then return kept, false end
    if last == nil then
        last, kept = now, 0
        return 0, false
    end
    local delta = now - last
    if delta <= 0 then
        -- Resync on the new reading; otherwise a backwards jump would blind the next frames.
        last = now
        return kept, false
    end
    if delta > GquestFrameTime.MAX_SECONDS then delta = GquestFrameTime.MAX_SECONDS end
    last, kept = now, delta
    return delta, true
end

function GquestFrameTime.Reset()
    last, kept = nil, 0
end
