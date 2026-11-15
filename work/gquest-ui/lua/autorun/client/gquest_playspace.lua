-- Snap turn for the playspace, without touching the native core.
--
-- The tracking provider already anchors the world on the engine player's view angles
-- (gquest_wrist_hud.lua: yaw = AngleDifference(player:EyeAngles().y, headAngle.y)). So
-- rotating the view yaw rotates the whole playspace, and every consumer follows along:
-- head, hands, aim poses and therefore the weapons. Keeping the maths here would be a
-- second implementation of what bridge/gquest_playspace.h already tests, so this file only
-- turns the view and leaves the arithmetic to the engine.
--
-- The recentre and the seated offset are deliberately not mirrored here: the tracking
-- provider anchors the head on the player's eye position, so what "recentre" means depends
-- on how the engine drives the camera, and guessing it would silently misalign every pose.
-- Both live in the native header, waiting for the platform split (decision E1).
GquestPlayspace = GquestPlayspace or {}
GquestPlayspace.STEP = 30

-- direction: 1 turns the view counter-clockwise, -1 clockwise. Anything else is refused
-- instead of being treated as a step, because a stray value means a broken binding.
function GquestPlayspace.SnapTurn(direction, step)
    step = step or GquestPlayspace.STEP
    if direction ~= 1 and direction ~= -1 then return false end
    if type(step) ~= "number" or step ~= step or step <= 0 or step > 180 then return false end
    if type(LocalPlayer) ~= "function" then return false end
    local player = LocalPlayer()
    if not IsValid(player) then return false end
    if type(player.EyeAngles) ~= "function" or type(player.SetEyeAngles) ~= "function" then
        return false
    end
    local eyes = player:EyeAngles()
    if type(eyes) ~= "table" or type(eyes.y) ~= "number" or eyes.y ~= eyes.y then return false end
    -- Pitch and roll stay as they are; only the heading is stepped. Normalising keeps the
    -- number in the same (-180, 180] window the native header uses.
    player:SetEyeAngles(Angle(eyes.p, math.NormalizeAngle(eyes.y + direction * step), eyes.r))
    return true
end

concommand.Add("gquest_snap_ccw", function() GquestPlayspace.SnapTurn(1) end)
concommand.Add("gquest_snap_cw", function() GquestPlayspace.SnapTurn(-1) end)
