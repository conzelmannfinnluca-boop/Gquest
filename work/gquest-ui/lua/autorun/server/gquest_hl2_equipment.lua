-- Native HL2 weapons retain their own VR models, ammunition and reload logic.
AddCSLuaFile()
local allowed={weapon_pistol=true,weapon_357=true,weapon_smg1=true,weapon_ar2=true,
    weapon_shotgun=true,weapon_crossbow=true,weapon_rpg=true,weapon_crowbar=true,
    weapon_frag=true,weapon_physcannon=true,weapon_physgun=true}
concommand.Add("gquest_hl2_equip",function(player,_,args)
    if not game.SinglePlayer() or not IsValid(player) or not player:Alive() then return end
    local class=args and args[1]
    if not allowed[class] then return end
    local weapon=player:GetWeapon(class)
    if not IsValid(weapon) then weapon=player:GetWeapon("hlvr_"..class) end
    if not IsValid(weapon) then weapon=player:Give(class) end
    if not IsValid(weapon) then return end
    player:SelectWeapon(weapon:GetClass())
    if GquestHL2Models then
        timer.Simple(0,function() GquestHL2Models.Apply(weapon) end)
    end
    print("GQUEST_HL2 equipped="..class.." model="..tostring(weapon:GetModel()))
end)

-- Assisted reload: move rounds from the player's own reserve into the active
-- weapon. Never creates ammunition -- the transfer is capped by the weapon's
-- own clip size and by the reserve the player actually has, and it is a no-op
-- when the native VR path already filled the magazine. Returns a reason string
-- so the caller can log exactly which boundary stopped it.
local function refill(player)
    if not IsValid(player) or not player:Alive() then return "no player" end
    local weapon=player:GetActiveWeapon()
    if not IsValid(weapon) then return "no weapon" end
    local maxClip=weapon:GetMaxClip1()
    local clip=weapon:Clip1()
    if not maxClip or maxClip<=0 or not clip or clip<0 then return "no magazine" end
    local missing=maxClip-clip
    if missing<=0 then return "already full" end
    local ammoType=weapon:GetPrimaryAmmoType()
    local reserve=player:GetAmmoCount(ammoType)
    local moved=math.min(missing,reserve)
    if moved<=0 then return "no reserve" end
    weapon:SetClip1(clip+moved)
    player:RemoveAmmo(moved,ammoType)
    return string.format("moved=%d clip=%d/%d reserve=%d",moved,weapon:Clip1(),maxClip,player:GetAmmoCount(ammoType))
end
concommand.Add("gquest_reload_refill",function(player)
    if not game.SinglePlayer() or not IsValid(player) then return end
    print("GQUEST_RELOAD_REFILL "..refill(player))
end)

-- Read-only state report. The native VR path keeps a magazine in its own
-- entity; this lists the candidates the engine logged for the held weapon so
-- the next device run can tell whether the clip the engine renders comes from
-- the weapon or from that entity. Nothing here writes to any entity.
concommand.Add("gquest_reload_state_sv",function(player)
    if not IsValid(player) then return end
    local weapon=player:GetActiveWeapon()
    if not IsValid(weapon) then print("GQUEST_RELOAD_STATE no weapon") return end
    local ammoType=weapon:GetPrimaryAmmoType()
    local quick=GetConVar("hlvr_quick_reload")
    local report={class=weapon:GetClass(),model=weapon:GetModel(),
        clip=weapon:Clip1(),maxClip=weapon:GetMaxClip1(),
        ammoType=ammoType,reserve=player:GetAmmoCount(ammoType),
        quick=quick and quick:GetString() or "absent",magazines={}}
    local base=weapon:GetClass()
    for _,entity in ipairs(ents.GetAll()) do
        if IsValid(entity) and entity~=weapon then
            local class=entity:GetClass()
            if string.sub(class,1,#base+1)==base.."_" then
                local owner=entity:GetOwner()
                report.magazines[#report.magazines+1]={class=class,
                    owner=IsValid(owner) and owner:GetClass() or "none"}
            end
        end
    end
    print("GQUEST_RELOAD_STATE "..util.TableToJSON(report,false))
end)
