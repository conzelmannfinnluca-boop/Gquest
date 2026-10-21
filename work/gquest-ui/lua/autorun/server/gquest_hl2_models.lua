-- Native HLVR entities otherwise keep the retail w_* model on this GMod build.
-- The matching shipped VR models carry the native grip/parts attachment frames.
-- Right-hand pistol alignment verified by the wearer on 2026-10-21.
AddCSLuaFile()
GquestHL2Models=GquestHL2Models or {}
local models={
    hlvr_weapon_pistol="models/weapons/vr_pistol.mdl",
    hlvr_weapon_357="models/weapons/vr_357.mdl",
    hlvr_weapon_smg1="models/weapons/vr_smg.mdl",
    hlvr_weapon_ar2="models/weapons/vr_irifle.mdl",
    hlvr_weapon_shotgun="models/weapons/vr_shotgun.mdl",
    hlvr_weapon_crossbow="models/weapons/vr_crossbow.mdl",
    hlvr_weapon_rpg="models/weapons/vr_rocket_launcher.mdl",
    hlvr_weapon_crowbar="models/weapons/vr_crowbar.mdl",
    hlvr_weapon_frag="models/weapons/vr_grenade.mdl",
    hlvr_weapon_bugbait="models/weapons/vr_bugbait.mdl",
    hlvr_weapon_physcannon="models/weapons/vr_physcannon.mdl",
}
local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)~=math.huge
end
function GquestHL2Models.RefreshGrips(weapon)
    if not weapon.GetSaveTable or not weapon.SetSaveValue then return false end
    local old=weapon:GetSaveTable()
    local keys,values={},{}
    local positions={}
    local function savedAngle(value) return isangle(value) or isvector(value) end
    local function frame(name,required)
        local index=weapon:LookupAttachment(name)
        if not index or index<=0 then return not required end
        local attachment=weapon:GetAttachment(index)
        if not attachment then return false end
        local pos,ang=WorldToLocal(attachment.Pos,attachment.Ang,weapon:GetPos(),weapon:GetAngles())
        if not isvector(pos) or not isangle(ang) or not
            (finite(pos.x) and finite(pos.y) and finite(pos.z) and finite(ang.p) and finite(ang.y) and finite(ang.r)) or
            math.abs(pos.x)>512 or math.abs(pos.y)>512 or math.abs(pos.z)>512 then return false end
        -- This melee model needs the opposite pitch correction from the
        -- rejected +90 trial. Confirmed on Quest3: shaft rises from the fist.
        -- Derive from the attachment every time, so Deploy cannot accumulate it.
        if name=="grip" and weapon:GetClass()=="hlvr_weapon_crowbar" then
            ang=Angle(ang.p-90,ang.y,ang.r)
        end
        local pk,ak="m_"..name.."LocalOffset","m_"..name.."LocalAngles"
        if not isvector(old[pk]) or not savedAngle(old[ak]) then return false end
        keys[#keys+1]=pk;values[#values+1]=pos
        keys[#keys+1]=ak;values[#values+1]=ang
        positions[name]=pos
        return true
    end
    -- Crowbar and other single-hand models have a grip but no foregrip.
    if not frame("grip",true) or not frame("foregrip",false) or not frame("muzzle",false) then return false end
    local separation
    if positions.foregrip then
        separation=positions.grip:DistToSqr(positions.foregrip)
        if separation<0.25 or separation>4096 then return false end
    end
    if positions.muzzle and type(old.m_bHasMuzzlePose)=="boolean" then
        keys[#keys+1]="m_bHasMuzzlePose";values[#values+1]=true
    end
    for i,key in ipairs(keys) do
        if weapon:SetSaveValue(key,values[i])~=true then
            for rollback=1,i do weapon:SetSaveValue(keys[rollback],old[keys[rollback]]) end
            return false
        end
    end
    print("GQUEST_HL2_GRIPS class="..weapon:GetClass().." separation="..tostring(separation and math.sqrt(separation))..
        " muzzle="..tostring(positions.muzzle~=nil).." fields="..#keys)
    return true
end
function GquestHL2Models.Apply(weapon)
    if not game.SinglePlayer() or not IsValid(weapon) then return false end
    local model=models[weapon:GetClass()]
    if not model then return false end
    local owner=weapon:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return false end
    if not file.Exists(model,"GAME") then return false end
    if weapon:GetModel()~=model then
        weapon:SetModel(model)
        print("GQUEST_HL2_MODEL class="..weapon:GetClass().." model="..model)
    end
    -- Native Spawn cached these fields before the old retail model was replaced.
    -- SetModel alone also leaves retail muzzle axes cached, so shots can miss
    -- the visible barrel direction. Refresh grip and muzzle frames together.
    GquestHL2Models.RefreshGrips(weapon)
    return true
end
local function afterDeploy(weapon)
    -- Deploy may reset the model after PlayerSwitchWeapon returns.
    timer.Simple(0,function() GquestHL2Models.Apply(weapon) end)
end
hook.Add("WeaponEquip","GquestHL2NativeModels",afterDeploy)
hook.Add("PlayerSwitchWeapon","GquestHL2NativeModels",function(_,_,weapon)
    afterDeploy(weapon)
end)
hook.Add("InitPostEntity","GquestHL2NativeModels",function()
    timer.Simple(0,function()
        for _,owner in ipairs(player.GetHumans()) do
            for _,weapon in ipairs(owner:GetWeapons()) do GquestHL2Models.Apply(weapon) end
        end
    end)
end)
