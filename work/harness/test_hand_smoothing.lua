-- Host test for the overlay's frame step and hand smoothing. Both modules work on plain
-- tables, so this needs no engine surface: the time is passed in, and the poses are numbers.
local function Near(actual, expected, tolerance)
    return math.abs(actual - expected) <= (tolerance or 0.001)
end

local function wrapDelta(from, to)
    return (to - from + 180) % 360 - 180
end

local function pose(x, y, z, p, yaw, r)
    return { pos = { x = x, y = y, z = z }, ang = { p = p or 0, y = yaw or 0, r = r or 0 } }
end

dofile("work/gquest-ui/lua/autorun/client/gquest_frame_time.lua")
dofile("work/gquest-ui/lua/autorun/client/gquest_hand_smoothing.lua")

-- --- Frame step -------------------------------------------------------------------------
GquestFrameTime.Reset()
local step, usable = GquestFrameTime.Step(10.0)
assert(step == 0 and not usable)  -- first reading only starts the timer

step, usable = GquestFrameTime.Step(10.0139)
assert(usable and Near(step, 0.0139))

-- The same reading twice in one frame holds the previous step, it does not measure zero.
step, usable = GquestFrameTime.Step(10.0139)
assert(not usable and Near(step, 0.0139))

-- A small step right after the resync is measurable: the timer does not stay blind.
step, usable = GquestFrameTime.Step(10.0200)
assert(usable and Near(step, 0.0061))

-- Ten seconds backwards is refused and resynced, so the next 20 ms is measurable again.
step, usable = GquestFrameTime.Step(0.02)
assert(not usable and Near(step, 0.0061))
step, usable = GquestFrameTime.Step(0.04)
assert(usable and Near(step, 0.02))

-- A three second stall is clamped to the same ceiling the core uses.
step, usable = GquestFrameTime.Step(3.04)
assert(usable and Near(step, GquestFrameTime.MAX_SECONDS) and Near(step, 0.5))

-- A broken reading is refused and the clamped step is kept.
step, usable = GquestFrameTime.Step(0 / 0)
assert(not usable and Near(step, 0.5))
step, usable = GquestFrameTime.Step(1 / 0)
assert(not usable and Near(step, 0.5))

-- --- Hand smoothing ---------------------------------------------------------------------
GquestHandSmoothing.Reset()
local out = GquestHandSmoothing.Apply(0, pose(0, 0, 0), 1 / 72, true)
assert(Near(out.pos.x, 0) and Near(out.ang.y, 0))  -- the first sample snaps

-- 30 ms time constant at 72 Hz: alpha = 1 - exp(-(1/72)/0.03) = 0.3704.
out = GquestHandSmoothing.Apply(0, pose(10, 0, 0), 1 / 72, true)
assert(Near(out.pos.x, 3.7037, 0.01))

-- Frame rate independence: two 1/36 steps and four 1/72 steps end in the same place.
GquestHandSmoothing.Reset()
GquestHandSmoothing.Apply(0, pose(0, 0, 0), 0, false)
for _ = 1, 2 do
    out = GquestHandSmoothing.Apply(0, pose(10, 0, 0), 1 / 36, true)
end
local fast = out.pos.x
GquestHandSmoothing.Reset()
GquestHandSmoothing.Apply(0, pose(0, 0, 0), 0, false)
for _ = 1, 4 do
    out = GquestHandSmoothing.Apply(0, pose(10, 0, 0), 1 / 72, true)
end
assert(Near(fast, out.pos.x, 0.01), "frame rate must not change the result")
assert(fast > 8 and fast < 9)  -- it really did move most of the way, not all of it

-- Without a usable step the published pose is held, not extrapolated. The module hands out
-- its own table, so the values are captured as numbers: keeping the table would make the next
-- call change the expectation it is compared against.
-- The step is a real one on purpose: a caller hands over the last kept step when the clock is
-- refused, so this case must not pass merely because the factor happens to be zero.
local beforeHold = out.pos.x
local held = GquestHandSmoothing.Apply(0, pose(100, 0, 0), 1 / 72, false)
assert(Near(held.pos.x, beforeHold) and held.pos.x < 100)

-- A teleport is not motion: beyond 24 inches the hand snaps instead of sliding.
local heldX = held.pos.x
out = GquestHandSmoothing.Apply(0, pose(heldX + 40, 0, 0), 1 / 72, true)
assert(Near(out.pos.x, heldX + 40))

-- Angles travel the short way across the seam: 170 -> -170 is 20 degrees, not 340.
GquestHandSmoothing.Reset()
GquestHandSmoothing.Apply(1, pose(0, 0, 0, 0, 170, 0), 0, false)
out = GquestHandSmoothing.Apply(1, pose(0, 0, 0, 0, -170, 0), 1 / 72, true)
-- 20 degrees of the short way, times the frame factor: 170 -> 177.41, not towards -170 the
-- long way round.
assert(Near(wrapDelta(170, out.ang.y), 20 * 0.3704, 0.01))
-- And it converges on the target rather than wandering off.
for _ = 1, 200 do
    out = GquestHandSmoothing.Apply(1, pose(0, 0, 0, 0, -170, 0), 1 / 72, true)
end
assert(Near(wrapDelta(out.ang.y, -170), 0, 0.001))

-- Hands keep separate state, and a reset makes the next sample snap again.
GquestHandSmoothing.Reset()
GquestHandSmoothing.Apply(0, pose(0, 0, 0), 0, false)
GquestHandSmoothing.Apply(0, pose(10, 0, 0), 1 / 72, true)
out = GquestHandSmoothing.Apply(1, pose(50, 0, 0), 1 / 72, true)
assert(Near(out.pos.x, 50), "the other hand must not start from the first hand's pose")
GquestHandSmoothing.Reset(0)
out = GquestHandSmoothing.Apply(0, pose(5, 0, 0), 1 / 72, true)
assert(Near(out.pos.x, 5), "after a reset the next sample snaps")

-- Disabled means pass-through, and a broken input is refused instead of throwing.
GquestHandSmoothing.Enabled = false
out = GquestHandSmoothing.Apply(0, pose(7, 8, 9, 1, 2, 3), 1 / 72, true)
assert(Near(out.pos.x, 7) and Near(out.pos.y, 8) and Near(out.ang.r, 3))
GquestHandSmoothing.Enabled = true
assert(GquestHandSmoothing.Apply(0, nil, 1 / 72, true) == nil)
assert(GquestHandSmoothing.Apply(0, { pos = { x = 0 } }, 1 / 72, true) == nil)

-- Levels: the menu stores a name, this module owns the time constant.
assert(GquestHandSmoothing.SetLevel("off"))
assert(not GquestHandSmoothing.Enabled)
GquestHandSmoothing.Reset()
GquestHandSmoothing.Apply(0, pose(0, 0, 0), 0, false)
out = GquestHandSmoothing.Apply(0, pose(10, 0, 0), 1 / 72, true)
assert(Near(out.pos.x, 10), "off must pass through")

assert(GquestHandSmoothing.SetLevel("mild") and GquestHandSmoothing.Enabled)
assert(Near(GquestHandSmoothing.TAU, 0.03))
assert(GquestHandSmoothing.SetLevel("strong") and Near(GquestHandSmoothing.TAU, 0.06))

-- The same step has to move a strongly smoothed hand less than a mildly smoothed one.
GquestHandSmoothing.Reset()
GquestHandSmoothing.SetLevel("mild")
GquestHandSmoothing.Apply(0, pose(0, 0, 0), 0, false)
local mildX = GquestHandSmoothing.Apply(0, pose(10, 0, 0), 1 / 72, true).pos.x
GquestHandSmoothing.Reset()
GquestHandSmoothing.SetLevel("strong")
GquestHandSmoothing.Apply(0, pose(0, 0, 0), 0, false)
local strongX = GquestHandSmoothing.Apply(0, pose(10, 0, 0), 1 / 72, true).pos.x
assert(strongX < mildX, "strong must lag more than mild")

-- An unknown name is refused and leaves the current setting alone.
assert(not GquestHandSmoothing.SetLevel("extreme"))
assert(Near(GquestHandSmoothing.TAU, 0.06) and GquestHandSmoothing.Enabled)
GquestHandSmoothing.SetLevel("mild")
GquestHandSmoothing.Reset()

print("PASS hand smoothing: frame step starts, measures, holds a repeated or broken reading "
    .. "and clamps a stall to 0.5 s; hands snap on the first sample, smooth by a factor taken "
    .. "from the step, end in the same place at 36 and 72 Hz, hold without a step, snap on a "
    .. "teleport and take the short way across the angle seam; the menu levels map off to "
    .. "pass-through and strong to a longer constant than mild, and an unknown level is "
    .. "refused without changing the setting")
