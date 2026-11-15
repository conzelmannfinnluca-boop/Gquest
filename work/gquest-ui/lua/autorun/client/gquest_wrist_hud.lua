-- Gquest native tracking provider. Wrist display removed at user request.
-- Native vr poses are in playspace Source units, not world coordinates.
GquestXR=GquestXR or {}
local function sourcePoseAngle(raw)
    -- The native API converts positions to (x,-z,y), but its Euler angles
    -- are still in the XR axes. Transform forward(-Z) and up(+Y) explicitly.
    local rotation=Angle(raw.p,raw.y,raw.r)
    local forward,up=Vector(0,0,-1),Vector(0,1,0)
    forward:Rotate(rotation);up:Rotate(rotation)
    forward=Vector(forward.x,-forward.z,forward.y)
    up=Vector(up.x,-up.z,up.y)
    return forward:AngleEx(up)
end
function GquestXR.GetWorldTracking()
    local player=LocalPlayer()
    if not IsValid(player) or not vr or not vr.GetHeadPose or not vr.GetHandPose then return end
    local head,headAngle,headValid=vr.GetHeadPose()
    if not headValid then return end
    -- This port's native pose binding returns field tables with legacy meta tags.
    -- Recreate actual Vector/Angle userdata before applying native math methods.
    head=Vector(head.x,head.y,head.z)
    headAngle=sourcePoseAngle(headAngle)
    local yaw=math.AngleDifference(player:EyeAngles().y,headAngle.y)
    local rotation=Angle(0,yaw,0)
    local headWorld=player:EyePos()
    -- One frame step per call, shared by both hands. A second call in the same frame gets
    -- "not usable" and therefore holds, instead of smoothing the same motion twice.
    local step,stepUsable=0,false
    if GquestFrameTime and GquestFrameTime.Step then
        step,stepUsable=GquestFrameTime.Step(RealTime())
    end
    local result={hmd={pos=headWorld,ang=player:EyeAngles()}}
    for hand=0,1 do
        local position,angle,valid=vr.GetHandPose(hand)
        if valid then
            position=Vector(position.x,position.y,position.z)
            angle=sourcePoseAngle(angle)
            local delta=position-head
            delta:Rotate(rotation)
            local worldAngle=Angle(angle.p,angle.y,angle.r)
            worldAngle:RotateAroundAxis(Vector(0,0,1),yaw)
            local worldPos=headWorld+delta
            -- The head is never smoothed: a lagging view is nauseating, a lagging hand reads
            -- as weight. See gquest_hand_smoothing.lua for the three rules.
            if GquestHandSmoothing and GquestHandSmoothing.Apply then
                local smoothed=GquestHandSmoothing.Apply(hand,{
                    pos={x=worldPos.x,y=worldPos.y,z=worldPos.z},
                    ang={p=worldAngle.p,y=worldAngle.y,r=worldAngle.r}},step,stepUsable)
                if smoothed then
                    worldPos=Vector(smoothed.pos.x,smoothed.pos.y,smoothed.pos.z)
                    worldAngle=Angle(smoothed.ang.p,smoothed.ang.y,smoothed.ang.r)
                end
            end
            result[hand==0 and "pose_lefthand" or "pose_righthand"]={pos=worldPos,ang=worldAngle}
        end
    end
    return result
end
-- Keep this legacy autorun path so an older extracted copy cannot re-enable
-- the wrist renderer after an APK update. The tracking API above is shared by
-- weapons and diagnostics and must remain available.
hook.Remove("PostDrawTranslucentRenderables","GquestWristHUD")
hook.Remove("HUDPaint","GquestVitals")
CreateClientConVar("gquest_wrist_hud","0",true,false,"Legacy wrist display (removed)")
RunConsoleCommand("gquest_wrist_hud","0")
print("GQUEST_WRIST removed: no hand display; native tracking provider preserved")
