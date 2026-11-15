-- Gquest native tracking provider (hand pipeline).
-- Wrist display removed at user request; this file is now only the pose chain:
--   vr.GetHandPose() -> axis conversion -> world transform -> smoothing -> published pose.
--
-- Four rules make a hand that stays on screen instead of breaking:
--   * one frame step per frame, cached by frame number, so both hands smooth with the same
--     step even when a consumer asks for each hand separately;
--   * a non-finite or invalid native sample holds the last published pose instead of
--     publishing a broken one - a NaN pose makes a hand disappear, and a missing key can drop
--     it to the origin;
--   * the last published pose is what the smoothing and the velocity use, so the numbers a
--     log shows are the numbers the game saw;
--   * velocity and angular velocity are computed from the published poses, because the
--     physics and throw paths read `vel`/`angvel` and a nil there is not "still", it is broken.
GquestXR = GquestXR or {}

local lastPublished = {}   -- [hand] = {pos=Vector, ang=Angle, vel=Vector, angvel=Angle}
local drops = {[0] = 0, [1] = 0}
local state = {}           -- [hand] = "ok" | "held"
local stepFrame, stepValue, stepUsable = nil, 0, false

local function finite(value)
    return type(value) == "number" and value == value and value > -1e9 and value < 1e9
end

local function readable(value)
    return type(value) == "table" and finite(value.x) and finite(value.y) and finite(value.z)
end

local function readableAngle(value)
    return type(value) == "table" and finite(value.p) and finite(value.y) and finite(value.r)
end

local function wrapDelta(from, to)
    return (to - from + 180) % 360 - 180
end

--- One real frame step per frame. A second call in the same frame reuses the first result
--- instead of asking the timer again and being told "no usable step" (which would freeze the
--- second hand that asked).
local function frameStep()
    if GquestFrameTime and GquestFrameTime.Step then
        if type(FrameNumber) == "function" then
            local frame = FrameNumber()
            if frame ~= stepFrame then
                stepFrame = frame
                stepValue, stepUsable = GquestFrameTime.Step(RealTime())
            end
            return stepValue, stepUsable
        end
        return GquestFrameTime.Step(RealTime())
    end
    return 0, false
end

local function sourcePoseAngle(raw)
    -- The native API converts positions to (x,-z,y), but its Euler angles
    -- are still in the XR axes. Transform forward(-Z) and up(+Y) explicitly.
    local rotation = Angle(raw.p, raw.y, raw.r)
    local forward, up = Vector(0, 0, -1), Vector(0, 1, 0)
    forward:Rotate(rotation)
    up:Rotate(rotation)
    forward = Vector(forward.x, -forward.z, forward.y)
    up = Vector(up.x, -up.z, up.y)
    return forward:AngleEx(up)
end

local function note(hand, name)
    if state[hand] == name then return end
    state[hand] = name
    print(string.format("GQUEST_HANDS hand=%s state=%s drops=%d",
        hand == 0 and "left" or "right", name, drops[hand]))
end

--- Build the published pose for one hand. `nil` means "nothing has ever been published for
--- this hand", which is the only case in which no key is written at all.
local function publish(hand, position, angle, step, usable)
    local previous = lastPublished[hand]
    local worldPos = position
    local worldAngle = angle
    if (GquestHandSmoothing and GquestHandSmoothing.Apply) then
        local smoothed = GquestHandSmoothing.Apply(hand, {
            pos = {x = worldPos.x, y = worldPos.y, z = worldPos.z},
            ang = {p = worldAngle.p, y = worldAngle.y, r = worldAngle.r}}, step, usable)
        if smoothed then
            worldPos = Vector(smoothed.pos.x, smoothed.pos.y, smoothed.pos.z)
            worldAngle = Angle(smoothed.ang.p, smoothed.ang.y, smoothed.ang.r)
        end
    end
    local pose = {pos = worldPos, ang = worldAngle, vel = Vector(), angvel = Angle()}
    if previous then
        local delta = worldPos - previous.pos
        local seconds = (usable and step > 0) and step or 0
        if seconds > 0 then
            pose.vel = delta / seconds
            pose.angvel = Angle(wrapDelta(previous.ang.p, worldAngle.p) / seconds,
                wrapDelta(previous.ang.y, worldAngle.y) / seconds,
                wrapDelta(previous.ang.r, worldAngle.r) / seconds)
        end
    end
    lastPublished[hand] = pose
    note(hand, "ok")
    return pose
end

--- Hold the last good pose. Copying it matters: the caller must not be able to mutate the
--- stored pose by writing into the table it was handed.
local function hold(hand)
    local previous = lastPublished[hand]
    if not previous then return nil end
    drops[hand] = drops[hand] + 1
    note(hand, "held")
    return {pos = Vector(previous.pos.x, previous.pos.y, previous.pos.z),
        ang = Angle(previous.ang.p, previous.ang.y, previous.ang.r),
        vel = Vector(), angvel = Angle(), held = true}
end

local memoFrame, memoResult

local function compute()
    local player = LocalPlayer()
    if not IsValid(player) or not vr or not vr.GetHeadPose or not vr.GetHandPose then return end
    local head, headAngle, headValid = vr.GetHeadPose()
    if not headValid or not readable(head) or not readableAngle(headAngle) then return end
    -- This port's native pose binding returns field tables with legacy meta tags.
    -- Recreate actual Vector/Angle userdata before applying native math methods.
    head = Vector(head.x, head.y, head.z)
    headAngle = sourcePoseAngle(headAngle)
    if not readableAngle(headAngle) then return end
    local yaw = math.AngleDifference(player:EyeAngles().y, headAngle.y)
    local rotation = Angle(0, yaw, 0)
    local headWorld = player:EyePos()
    -- One frame step per frame, shared by both hands.
    local step, usable = frameStep()
    local result = {hmd = {pos = headWorld, ang = player:EyeAngles()}}
    for hand = 0, 1 do
        local key = hand == 0 and "pose_lefthand" or "pose_righthand"
        local position, angle, valid = vr.GetHandPose(hand)
        local pose
        if valid and readable(position) and readableAngle(angle) then
            local worldPos = Vector(position.x, position.y, position.z)
            local sourceAngle = sourcePoseAngle(angle)
            if readableAngle(sourceAngle) and readable(worldPos) then
                local delta = worldPos - head
                delta:Rotate(rotation)
                local worldAngle = Angle(sourceAngle.p, sourceAngle.y, sourceAngle.r)
                worldAngle:RotateAroundAxis(Vector(0, 0, 1), yaw)
                if readableAngle(worldAngle) and readable(headWorld + delta) then
                    pose = publish(hand, headWorld + delta, worldAngle, step, usable)
                end
            end
        end
        if not pose then pose = hold(hand) end
        if pose then
            result[key] = {pos = pose.pos, ang = pose.ang, vel = pose.vel, angvel = pose.angvel,
                held = pose.held}
        end
    end
    return result
end

--- One computed result per frame. A second call in the same frame returns the cached result
--- instead of smoothing the same motion twice, which would make the hand lag behind the very
--- input it is meant to follow.
function GquestXR.GetWorldTracking()
    if type(FrameNumber) == "function" then
        local frame = FrameNumber()
        if memoFrame == frame and memoResult then return memoResult end
        memoResult = compute()
        memoFrame = frame
        return memoResult
    end
    return compute()
end

--- Forget one hand (or both). The next sample snaps and the held pose is dropped.
function GquestXR.ResetHand(hand)
    -- The filter keeps its own state; without this a recentre would slide to the new pose
    -- instead of starting there, which is exactly the lag a reset is meant to remove.
    if GquestHandSmoothing and GquestHandSmoothing.Reset then GquestHandSmoothing.Reset(hand) end
    if hand == nil then
        lastPublished = {}
        state = {}
    else
        lastPublished[hand] = nil
        state[hand] = nil
    end
end

function GquestXR.DescribeHands()
    return string.format("GQUEST_HANDS state left=%s drops=%d right=%s drops=%d",
        tostring(state[0]), drops[0], tostring(state[1]), drops[1])
end

-- Keep this legacy autorun path so an older extracted copy cannot re-enable
-- the wrist renderer after an APK update. The tracking API above is shared by
-- weapons and diagnostics and must remain available.
hook.Remove("PostDrawTranslucentRenderables", "GquestWristHUD")
hook.Remove("HUDPaint", "GquestVitals")
CreateClientConVar("gquest_wrist_hud", "0", true, false, "Legacy wrist display (removed)")
RunConsoleCommand("gquest_wrist_hud", "0")
concommand.Add("gquest_hands_state", function()
    print(GquestXR.DescribeHands())
    for hand = 0, 1 do
        local pose = lastPublished[hand]
        if pose then
            print(string.format("GQUEST_HANDS hand=%s pos=%.2f,%.2f,%.2f ang=%.2f,%.2f,%.2f vel=%.1f",
                hand == 0 and "left" or "right", pose.pos.x, pose.pos.y, pose.pos.z,
                pose.ang.p, pose.ang.y, pose.ang.r, pose.vel:Length()))
        end
    end
end)
print("GQUEST_WRIST removed: no hand display; native tracking provider preserved")
