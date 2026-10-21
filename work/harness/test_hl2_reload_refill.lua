-- Boundary harness for the server-side assisted reload refill.
-- The refill must only move rounds the player already owns.
local commands={}
concommand={Add=function(key,fn) commands[key]=fn end}
function IsValid(v) return type(v)=="table" end
game={SinglePlayer=function() return true end}
ents={GetAll=function() return {} end}
util={TableToJSON=function(t) return "{}" end}
local cvars={hlvr_quick_reload={GetString=function() return "1" end}}
function GetConVar(name) return cvars[name] end
AddCSLuaFile=function() end
timer={Simple=function(_,fn) fn() end}
player={GetHumans=function() return {} end}
dofile("work/gquest-ui/lua/autorun/server/gquest_hl2_equipment.lua")

local function makeWeapon(clip,maxClip,ammoType)
    return {GetClass=function() return "weapon_smg1" end,
        GetModel=function() return "models/weapons/vr_smg.mdl" end,
        Clip1=function() return clip end,SetClip1=function(_,v) clip=v end,
        GetMaxClip1=function() return maxClip end,
        GetPrimaryAmmoType=function() return ammoType end,
        GetOwner=function() return nil end}
end
local function makePlayer(weapon,reserve,alive)
    local counts={}
    local p={Alive=function() return alive~=false end,
        GetActiveWeapon=function() return weapon end,
        GetAmmoCount=function(_,t) return counts[t] or reserve end,
        RemoveAmmo=function(_,n,t) counts[t]=(counts[t] or reserve)-n end,
        GetWeapon=function() return weapon end,
        SetAmmo=function(_,n,t) counts[t]=n end}
    return p
end

-- Partial magazine: only the missing rounds move.
local w=makeWeapon(10,45,4)
local p=makePlayer(w,100)
commands.gquest_reload_refill(p)
assert(w.Clip1()==45,"magazine must fill to its own maximum")
assert(p:GetAmmoCount(4)==65,"exactly 35 rounds leave the reserve")

-- Reserve smaller than the gap: never invents ammunition.
w=makeWeapon(0,45,4);p=makePlayer(w,7)
commands.gquest_reload_refill(p)
assert(w.Clip1()==7,"clip must stop at the reserve actually held")
assert(p:GetAmmoCount(4)==0,"reserve must not go negative")

-- Empty reserve is a no-op.
w=makeWeapon(0,45,4);p=makePlayer(w,0)
commands.gquest_reload_refill(p)
assert(w.Clip1()==0 and p:GetAmmoCount(4)==0,"empty reserve must change nothing")

-- Already full is a no-op.
w=makeWeapon(45,45,4);p=makePlayer(w,100)
commands.gquest_reload_refill(p)
assert(w.Clip1()==45 and p:GetAmmoCount(4)==100,"full magazine must not consume reserve")

-- Weapons without a magazine (crowbar, physgun, grenade) stay untouched.
w=makeWeapon(0,0,0);p=makePlayer(w,50)
commands.gquest_reload_refill(p)
assert(w.Clip1()==0 and p:GetAmmoCount(0)==50,"magazineless weapon must be left alone")

-- Dead player and missing weapon are refused.
w=makeWeapon(0,45,4);p=makePlayer(w,100,false)
commands.gquest_reload_refill(p)
assert(w.Clip1()==0,"dead player must not be refilled")
commands.gquest_reload_refill({Alive=function() return true end,GetActiveWeapon=function() return nil end})

print("PASS assisted reload refill: clip cap, reserve cap, empty reserve, full magazine, magazineless weapon, dead player")

-- Real native weapons consume magazine state, not the base Clip1 field.
local function native(held,reserve,options)
 options=options or {}
 local w=makeWeapon(10,45,4)
 w.GetClass=function() return "hlvr_weapon_smg1" end
 local mag={}
 local data={m_iCurrentAmmoCount=held,m_iMaxAmmoCount=45,m_hLoadedWeapon=w}
 local ws={m_hLoadedMagazine=mag,m_iChamberedRounds=1,m_eMagazineState=2}
 w.GetSaveTable=function() return ws end
 mag.GetSaveTable=function() return data end
 local fail=options.fail
 mag.SetSaveValue=function(_,key,value)
  assert(key=="m_iCurrentAmmoCount")
  if fail then fail=false;data[key]=value;return false end
  data[key]=value;return true
 end
 return w,makePlayer(w,reserve),data,ws
end
w,p=makeWeapon(10,45,4),nil
local mag,ws
w,p,mag,ws=native(2,100)
commands.gquest_reload_refill(p)
assert(mag.m_iCurrentAmmoCount==45 and p:GetAmmoCount(4)==57)
assert(w.Clip1()==10 and ws.m_iChamberedRounds==1 and ws.m_eMagazineState==2,"native reload fabricated base clip/chamber/state")
w,p,mag=native(2,7);commands.gquest_reload_refill(p)
assert(mag.m_iCurrentAmmoCount==9 and p:GetAmmoCount(4)==0,"native reserve cap failed")
w,p,mag=native(2,100,{fail=true});commands.gquest_reload_refill(p)
assert(mag.m_iCurrentAmmoCount==2 and p:GetAmmoCount(4)==100,"failed native write did not restore magazine/reserve")
w,p,mag=native(45,100);commands.gquest_reload_refill(p)
assert(mag.m_iCurrentAmmoCount==45 and p:GetAmmoCount(4)==100,"full native magazine consumed reserve")
w,p,mag=native(2,100);mag.m_hLoadedWeapon={};commands.gquest_reload_refill(p)
assert(mag.m_iCurrentAmmoCount==2 and p:GetAmmoCount(4)==100,"foreign native magazine changed")
w,p,mag=native(2,100);mag.m_iMaxAmmoCount=0/0;commands.gquest_reload_refill(p)
assert(mag.m_iCurrentAmmoCount==2 and p:GetAmmoCount(4)==100,"nonfinite native capacity changed ammo")
w,p,mag,ws=native(2,100);ws.m_hLoadedMagazine=nil;commands.gquest_reload_refill(p)
assert(mag.m_iCurrentAmmoCount==2 and w.Clip1()==10 and p:GetAmmoCount(4)==100,"missing native magazine wrote base clip")
print("PASS native magazine reload: actual linked magazine, no fabricated chamber/base clip, own reserve cap, write rollback, foreign/nonfinite/missing-mag guards")
