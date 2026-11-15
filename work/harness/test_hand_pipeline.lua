-- Boundary harness for the hand pipeline in gquest_wrist_hud.lua.
--
-- There is no GMod here, so the file supplies small Vector/Angle stand-ins with only the
-- operations the provider uses. They are not a claim about Source's maths - what this checks is
-- the pipeline's behaviour: one result per frame, a held pose on a broken sample, a NaN gate,
-- velocity from the published poses, and a working reset.
local VECTOR = {}
VECTOR.__index = VECTOR
function VECTOR:Length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end
function VECTOR:Rotate(angle)
    local yaw, pitch = math.rad(angle.y), math.rad(angle.p)
    local x = self.x * math.cos(yaw) - self.y * math.sin(yaw)
    local y = self.x * math.sin(yaw) + self.y * math.cos(yaw)
    local z = self.z
    local z2 = -x * math.sin(pitch) + z * math.cos(pitch)
    local x2 = x * math.cos(pitch) + z * math.sin(pitch)
    self.x, self.y, self.z = x2, y, z2
    return self
end
function VECTOR:AngleEx(up)
    local length = self:Length()
    if length == 0 then return setmetatable({p = 0, y = 0, r = 0}, ANGLE) end
    local fx, fy, fz = self.x / length, self.y / length, self.z / length
    local p = -math.deg(math.asin(math.max(-1, math.min(1, fz))))
    local y = math.deg(math.atan(fy, fx))
    -- Right vector = forward x world up, roll = angle between up and right.
    local rx, ry = -fy, fx
    local roll = math.deg(math.atan(up.x * rx + up.y * ry, math.max(1e-6, up.z)))
    return setmetatable({p = p, y = y, r = roll}, ANGLE)
end
VECTOR.__add = function(a, b) return setmetatable({x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}, VECTOR) end
VECTOR.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, VECTOR) end
VECTOR.__div = function(a, b) return setmetatable({x = a.x / b, y = a.y / b, z = a.z / b}, VECTOR) end
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, VECTOR) end

local ANGLE = {}
ANGLE.__index = ANGLE
function ANGLE:RotateAroundAxis(axis, degrees)
    if math.abs(axis.z) > 0.5 then self.y = self.y + degrees end
    return self
end
function Angle(p, y, r) return setmetatable({p = p or 0, y = y or 0, r = r or 0}, ANGLE) end

math.AngleDifference = function(a, b)
    local difference = (b - a + 180) % 360 - 180
    return difference
end

-- Frame clock the harness drives by hand.
local frame, now = 0, 0
function FrameNumber() return frame end
function RealTime() return now end
local function advance(seconds)
    frame = frame + 1
    now = now + (seconds or 1 / 72)
end

local cvars, commands, hooks = {}, {}, {}
function CreateClientConVar(name, value)
    local entry = {value = value}
    entry.GetBool = function() return value ~= "0" end
    entry.GetFloat = function() return tonumber(value) or 0 end
    cvars[name] = entry
    return entry
end
function GetConVar(name) return cvars[name] end
function RunConsoleCommand() end
concommand = {Add = function(name, fn) commands[name] = fn end}
hook = {Add = function() end, Remove = function() end}
function IsValid(value) return type(value) == "table" end
local player_ = {EyePos = function() return Vector(0, 0, 64) end, EyeAngles = function() return Angle(0, 0, 0) end}
function LocalPlayer() return player_ end

-- Native side: two hands, driven by the test.
local native = {
    [0] = {pos = Vector(-10, 0, 0), ang = Angle(0, 0, 0), valid = true},
    [1] = {pos = Vector(10, 0, 0), ang = Angle(0, 0, 0), valid = true},
}
vr = {
    GetHeadPose = function() return {x = 0, y = 0, z = 0}, {p = 0, y = 0, r = 0}, true end,
    GetHandPose = function(hand)
        local entry = native[hand]
        return entry.pos, entry.ang, entry.valid
    end,
    GetPrimaryHand = function() return 1 end,
    IsActive = function() return true end,
}

dofile("work/gquest-ui/lua/autorun/client/gquest_frame_time.lua")
dofile("work/gquest-ui/lua/autorun/client/gquest_hand_smoothing.lua")
GquestHandSmoothing.SetLevel("mild")
dofile("work/gquest-ui/lua/autorun/client/gquest_wrist_hud.lua")

-- First sample: both hands published, nothing held, no invented velocity.
local first = GquestXR.GetWorldTracking()
assert(first and first.pose_lefthand and first.pose_righthand, "both hands must be published")
assert(first.pose_lefthand.vel ~= nil and first.pose_righthand.angvel ~= nil,
    "velocity fields must exist so physics and throw paths never read nil")
assert(math.abs(first.pose_lefthand.vel:Length()) < 1e-6, "the first sample has no motion to report")
assert(not first.pose_lefthand.held, "a valid first sample must not be marked held")

-- One result per frame: a second call returns the cached table instead of smoothing twice.
local again = GquestXR.GetWorldTracking()
assert(again == first, "a second call in the same frame must reuse the computed result")

-- Next frame, both hands move: the published pose follows and reports a velocity.
advance()
native[0].pos = Vector(-9, 0, 0)
native[1].pos = Vector(9, 0, 0)
local second = GquestXR.GetWorldTracking()
assert(second ~= first, "a new frame must compute a new result")
assert(second.pose_lefthand.pos.x > first.pose_lefthand.pos.x, "the left hand must move towards its sample")
assert(second.pose_lefthand.vel:Length() > 0, "a moving hand must report a velocity")
assert(second.pose_righthand.pos.x < first.pose_righthand.pos.x, "the right hand must move too")

-- A non-finite sample holds the last good pose instead of publishing a broken one.
advance()
local goodLeft = second.pose_lefthand.pos.x
native[0].pos = Vector(0 / 0, 0, 0)
local third = GquestXR.GetWorldTracking()
assert(third.pose_lefthand.held, "a NaN sample must be held, not published")
assert(math.abs(third.pose_lefthand.pos.x - goodLeft) < 1e-9, "the held pose must stay where it was")
assert(string.find(GquestXR.DescribeHands(), "drops=1"), "a held hand must be counted")
assert(third.pose_lefthand.vel:Length() == 0, "a held pose reports no motion")

-- An invalid sample does the same, and the hand recovers on the next valid one.
advance()
native[0].valid = false
native[0].pos = Vector(-8, 0, 0)
local fourth = GquestXR.GetWorldTracking()
assert(fourth.pose_lefthand.held, "an invalid sample must hold")
advance()
native[0].valid = true
local fifth = GquestXR.GetWorldTracking()
assert(not fifth.pose_lefthand.held, "a valid sample must resume publishing")

-- The held pose is a copy: mutating it must not move the stored state.
local held = fourth.pose_lefthand
held.pos.x = 999
advance()
local sixth = GquestXR.GetWorldTracking()
assert(sixth.pose_lefthand.pos.x < 100, "the stored pose must not be reachable from the caller")

-- Reset makes the next sample snap, so a recentre cannot slide across the map. The reference
-- is the same sample with smoothing switched off, which is what "no filter at all" means.
GquestXR.ResetHand(0)
native[0].pos = Vector(-30, 7, 3)
advance()
local seventh = GquestXR.GetWorldTracking()
local snapped = {x = seventh.pose_lefthand.pos.x, y = seventh.pose_lefthand.pos.y, z = seventh.pose_lefthand.pos.z}
GquestHandSmoothing.SetLevel("off")
GquestXR.ResetHand(0)
advance()
local reference = GquestXR.GetWorldTracking()
assert(math.abs(reference.pose_lefthand.pos.x - snapped.x) < 1e-6
    and math.abs(reference.pose_lefthand.pos.y - snapped.y) < 1e-6
    and math.abs(reference.pose_lefthand.pos.z - snapped.z) < 1e-6,
    "after a reset the next sample must snap to the unfiltered pose")

-- Diagnostics are readable without a headset.
commands.gquest_hands_state()

print("PASS hand pipeline: both hands published, one result per frame, held pose on NaN and "
    .. "invalid samples, velocity from published poses, copy isolation, reset snap, diagnostics")
