-- Host test for the Lua snap turn. Runs the shipped file against a fake player, so the
-- assertions are about the module's decisions (what it refuses, what it preserves) and not
-- about the engine.
local yaw, pitch, roll = 0, 12, -3
local setCalls = 0
local playerPresent = true

local function player()
    return {
        EyeAngles = function() return { p = pitch, y = yaw, r = roll } end,
        SetEyeAngles = function(_, angle)
            setCalls = setCalls + 1
            pitch, yaw, roll = angle.p, angle.y, angle.r
        end,
    }
end

function Angle(p, y, r) return { p = p, y = y, r = r } end
function IsValid(value) return playerPresent and value ~= nil end
function LocalPlayer() return player() end
-- Garry's Mod provides this; the stub matches its documented (-180, 180] range.
math.NormalizeAngle = function(value)
    local wrapped = ((value + 180) % 360) - 180
    if wrapped == -180 then return 180 end
    return wrapped
end

local commands = {}
concommand = { Add = function(name, fn) commands[name] = fn end }

dofile("work/gquest-ui/lua/autorun/client/gquest_playspace.lua")

assert(GquestPlayspace.STEP == 30)
assert(type(commands.gquest_snap_ccw) == "function")
assert(type(commands.gquest_snap_cw) == "function")

-- One step each way, with pitch and roll untouched.
assert(GquestPlayspace.SnapTurn(1))
assert(yaw == 30 and pitch == 12 and roll == -3)
assert(GquestPlayspace.SnapTurn(-1))
assert(yaw == 0 and pitch == 12 and roll == -3)

-- The console commands are the two directions; their names state the direction so a binding
-- cannot silently mean the opposite.
commands.gquest_snap_ccw()
assert(yaw == 30)
commands.gquest_snap_cw()
assert(yaw == 0)

-- A custom step is honoured and the heading wraps across the seam both ways.
yaw = 170
assert(GquestPlayspace.SnapTurn(1))
assert(yaw == -160)
assert(GquestPlayspace.SnapTurn(-1))
assert(yaw == 170)
yaw = -170
assert(GquestPlayspace.SnapTurn(-1))   -- -200 lands on +160, not on -160
assert(yaw == 160)
yaw = -150
assert(GquestPlayspace.SnapTurn(-1, 60))
assert(yaw == 150)

-- Refusals leave the heading exactly as it was, and do not touch the player at all.
local function refused(...)
    local before = { yaw = yaw, calls = setCalls }
    assert(GquestPlayspace.SnapTurn(...) == false)
    assert(yaw == before.yaw and setCalls == before.calls)
end
yaw = 40
refused(0)
refused(2)
refused(-2)
refused(1, 0)
refused(1, -30)
refused(1, 181)
refused(1, 0 / 0)
refused(1, "30")
refused(nil)

-- A missing or broken player is refused rather than throwing a Lua error.
playerPresent = false
local savedLocalPlayer = LocalPlayer
LocalPlayer = function() return nil end
assert(GquestPlayspace.SnapTurn(1) == false)
LocalPlayer = savedLocalPlayer
playerPresent = true
local broken = LocalPlayer
LocalPlayer = function() return {} end
assert(GquestPlayspace.SnapTurn(1) == false)
LocalPlayer = broken
assert(yaw == 40)

print("PASS playspace lua: snap turn steps both ways by 30 degrees with pitch and roll kept, "
    .. "custom step honoured, heading wrapped across both seams, invalid directions, steps, "
    .. "types and a missing player refused without touching the view")
