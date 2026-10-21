-- Manual native magazine insertion and racking are the Gquest default.
-- Optional assistance uses real linked magazine state, never the retail clip.
GquestReload=GquestReload or {}
local assisted=CreateClientConVar("gquest_reload_assisted","1",true,false,
    "Assisted HL2 reload: native eject, then refill the magazine from the player's own reserve")
local physical=CreateClientConVar("gquest_reload_physical","1",true,false,
    "Manual VR reload: grab a magazine at the hip, insert it and rack the weapon")
local function assistedEnabled() return assisted:GetBool() and not physical:GetBool() end
local releaseAt,refillAt,pendingWeapon
local ejectWasDown=false
local reloadable={hlvr_weapon_pistol=true,hlvr_weapon_357=true,hlvr_weapon_smg1=true,
    hlvr_weapon_ar2=true,hlvr_weapon_shotgun=true,hlvr_weapon_crossbow=true,hlvr_weapon_rpg=true}
local function release()
    if releaseAt then RunConsoleCommand("-eject");releaseAt=nil end
end
local function refill()
    refillAt=nil
    local p=LocalPlayer()
    local w=pendingWeapon;pendingWeapon=nil
    if not IsValid(p) or not p:Alive() or not IsValid(w) or p:GetActiveWeapon()~=w then
        print("GQUEST_RELOAD cancelled: weapon changed or player unavailable")
        return
    end
    RunConsoleCommand("gquest_reload_refill")
end
local function applyMode()
    if not assistedEnabled() then refillAt=nil;pendingWeapon=nil end
    if GetConVar("hlvr_quick_reload") then
        RunConsoleCommand("hlvr_quick_reload",assistedEnabled() and "1" or "0")
    end
    if physical:GetBool() then
        -- Native hand items enable the engine's actual magazine-pouch grabs.
        if GetConVar("hlvr_hand_items") then RunConsoleCommand("hlvr_hand_items","1") end
        if GetConVar("hlvr_ammo_holster_location") then RunConsoleCommand("hlvr_ammo_holster_location","1") end
    end
end
hook.Add("InitPostEntity","GquestReloadMode",applyMode)
cvars.AddChangeCallback("gquest_reload_assisted",applyMode,"GquestReloadMode")
cvars.AddChangeCallback("gquest_reload_physical",applyMode,"GquestReloadPhysicalMode")
local function request(nativeEject)
    local p=LocalPlayer()
    if not IsValid(p) or not p:Alive() then return end
    local w=p:GetActiveWeapon()
    if not IsValid(w) or not reloadable[w:GetClass()] or refillAt then return end
    applyMode()
    -- The engine already consumes weapon/eject from the Touch button. Sending
    -- another +eject here would eject twice; only menu/console requests pulse it.
    if not nativeEject then
        RunConsoleCommand("+eject")
        releaseAt=RealTime()+0.18
    end
    -- The refill runs after the eject pulse has been released, so the native
    -- path gets the full gesture before Lua tops the magazine up.
    if assistedEnabled() then pendingWeapon=w;refillAt=RealTime()+0.45 end
    if chat and chat.AddText then chat.AddText("Magazin auswerfen, links an der Huefte ein neues greifen, einsetzen und durchladen.") end
    print("GQUEST_RELOAD requested="..w:GetClass().." assisted="..tostring(assistedEnabled()))
end
function GquestReload.Request() request(false) end
concommand.Add("gquest_reload",GquestReload.Request)
concommand.Add("gquest_reload_state",function() RunConsoleCommand("gquest_reload_state_sv") end)
hook.Add("Think","GquestReloadRelease",function()
    if vr and vr.GetActionDigital then
        local hand=vr.GetPrimaryHand and vr.GetPrimaryHand() or 1
        local down,changed,active=vr.GetActionDigital("weapon","eject",hand)
        if active and down and changed and not ejectWasDown then request(true) end
        ejectWasDown=active and down or false
    end
    if releaseAt and RealTime()>=releaseAt then release() end
    if refillAt and RealTime()>=refillAt then refill() end
end)
hook.Add("ShutDown","GquestReloadRelease",function() release();refillAt=nil;pendingWeapon=nil end)
print("GQUEST_RELOAD ready: native manual magazines; optional linked-magazine assistance")
