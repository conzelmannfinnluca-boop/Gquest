-- GQuest: gesture side of the manual weapon mechanics.
--
-- The server module (gquest_weapon_mechanics.lua) owns the state machine; this file only turns
-- hand motion and buttons into its commands. Two gestures, both deliberately narrow so a
-- normal firefight cannot trigger them by accident:
--
--   * the primary hand's eject action drops or inserts the magazine (engine action the native
--     path already exposes, the same one the reload module listens to);
--   * the support hand, close to the weapon, pulled backwards quickly racks the weapon.
--
-- The rack gesture is geometric and therefore unverified on hardware: the weapon's own
-- "slide" attachment is used when the model has one, otherwise its origin, and every rejected
-- candidate writes one diagnostic line naming the reason. That line is the tuning input for the
-- next headset run - it is not proof that the gesture feels right.
GquestMechGestures = GquestMechGestures or {}

local enabled = CreateClientConVar("gquest_mech_gestures", "1", true, false,
    "Support-hand racking gesture and magazine button for the manual weapon mechanics")
local reach = CreateClientConVar("gquest_mech_reach", "6", true, false,
    "How close (units) the support hand must be to the weapon to rack it")
local travel = CreateClientConVar("gquest_mech_travel", "4", true, false,
    "How far (units) the support hand must travel backwards to rack the weapon")

-- The rules live in the server module, which is deliberately not sent to clients. The
-- client only needs to know which weapons have mechanics, so the class list is repeated here
-- rather than shipping the whole state machine to the headset.
local MECHANICS = {
    weapon_pistol = true, weapon_smg1 = true, weapon_ar2 = true, weapon_357 = true,
    weapon_shotgun = true, weapon_crossbow = true, weapon_rpg = true,
}

local function mechanical(class)
    if type(class) ~= "string" then return false end
    if string.sub(class, 1, 5) == "hlvr_" then class = string.sub(class, 6) end
    return MECHANICS[class] == true
end

local lastRack, lastMag = 0, 0
local previous, reportedAction = nil, {}

local function finite(value)
    return type(value) == "number" and value == value and value > -1e9 and value < 1e9
end

local function actionState(name)
    if not vr or not vr.GetActionDigital then return nil end
    local hand = vr.GetPrimaryHand and vr.GetPrimaryHand() or 1
    local down, changed, active = vr.GetActionDigital("weapon", name, hand)
    if not active and not reportedAction[name] then
        reportedAction[name] = true
        print("GQUEST_MECHGESTURE action_inactive=" .. name)
    end
    return down, changed, active
end

local function rackPoint(weapon)
    local attachment = weapon.LookupAttachment and weapon:LookupAttachment("slide") or 0
    if attachment and attachment > 0 then
        local data = weapon:GetAttachment(attachment)
        if data and data.Pos then return data.Pos, data.Ang end
    end
    return weapon:GetPos(), weapon:GetAngles()
end

--- Support hand in weapon space: negative forward means "behind the anchor", which is the
--- direction a slide or bolt is pulled.
local function handInWeaponSpace(weapon)
    if not vr or not vr.GetHandPose then return nil end
    local hand = vr.GetPrimaryHand and vr.GetPrimaryHand() or 1
    local support = hand == 1 and 0 or 1
    local position, _, valid = vr.GetHandPose(support)
    if not valid or not position then return nil end
    local anchor, angles = rackPoint(weapon)
    if not anchor or not angles then return nil end
    local world = Vector(position.x, position.y, position.z)
    local local_ = WorldToLocal(world, Angle(), anchor, angles)
    return local_, support
end

hook.Add("Think", "GquestMechGestures", function()
    local player = LocalPlayer()
    if not IsValid(player) or not player:Alive() then previous = nil return end
    local weapon = player:GetActiveWeapon()
    if not IsValid(weapon) or not mechanical(weapon:GetClass()) then previous = nil return end
    if not enabled:GetBool() or not (vr and vr.IsActive and vr.IsActive()) then previous = nil return end

    -- Magazine: the engine's own eject action, edge triggered.
    local down, changed, active = actionState("eject")
    if active and down and changed and RealTime() - lastMag > 0.5 then
        lastMag = RealTime()
        RunConsoleCommand("gquest_mech_mag")
        print("GQUEST_MECHGESTURE mag class=" .. weapon:GetClass())
    end

    -- Rack: support hand near the weapon and moving backwards.
    local localPos = handInWeaponSpace(weapon)
    if not localPos then previous = nil return end
    local now = RealTime()
    if previous and now - previous.at <= 0.35 then
        local dx = localPos.x - previous.x
        local distance = math.sqrt(localPos.x * localPos.x + localPos.y * localPos.y + localPos.z * localPos.z)
        local movedBack = -dx
        if distance <= reach:GetFloat() and movedBack >= travel:GetFloat() and now - lastRack > 0.6 then
            lastRack = now
            RunConsoleCommand("gquest_mech_rack")
            print(string.format("GQUEST_MECHGESTURE rack class=%s distance=%.2f travel=%.2f",
                weapon:GetClass(), distance, movedBack))
            previous = nil
            return
        end
    end
    previous = {x = localPos.x, at = now}
end)

if GquestMechGestures then
    function GquestMechGestures.IsEnabled() return enabled:GetBool() end
end

print("GQUEST_MECHGESTURE ready: eject action drops/inserts the magazine, support hand racks")
