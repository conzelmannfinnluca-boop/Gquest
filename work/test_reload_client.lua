-- Execute the real client reload dispatcher; native command boundary is mocked.
local hooks,commands,callbacks={},{},{}
local now=0
local mode=true
local physicalMode=false
local events={}
local player={Alive=function() return true end}
local weapon={GetClass=function() return "hlvr_weapon_smg1" end}
function player:GetActiveWeapon() return weapon end
function LocalPlayer() return player end
function IsValid(v) return type(v)=="table" end
function CreateClientConVar(name) return {GetBool=function() return name=="gquest_reload_physical" and physicalMode or (name~="gquest_reload_physical" and mode) end} end
function GetConVar(name) assert(name=="hlvr_quick_reload" or name=="hlvr_hand_items" or name=="hlvr_ammo_holster_location");return {} end
function RealTime() return now end
function RunConsoleCommand(name,value) events[#events+1]={name,value} end
hook={Add=function(event,key,fn)
 local old=hooks[event]
 hooks[event]=old and function() old();fn() end or fn
end}
concommand={Add=function(key,fn) commands[key]=fn end}
cvars={AddChangeCallback=function(key,fn) callbacks[key]=fn end}
dofile("work/gquest-ui/lua/autorun/client/gquest_reload.lua")
hooks.InitPostEntity();assert(events[#events][1]=="hlvr_quick_reload" and events[#events][2]=="1")
commands.gquest_reload();assert(events[#events][1]=="+eject")
-- The refill must not run before the eject pulse is released.
now=0.1;hooks.Think();assert(events[#events][1]=="+eject")
now=0.2;hooks.Think();assert(events[#events][1]=="-eject")
now=0.3;hooks.Think();assert(events[#events][1]=="-eject","refill ran before its delay")
now=0.5;hooks.Think();assert(events[#events][1]=="gquest_reload_refill")
local afterRefill=#events;hooks.Think();assert(#events==afterRefill,"refill must fire once")
-- Assisted mode off keeps the plain native path: no refill is ever queued.
mode=false;callbacks.gquest_reload_assisted();assert(events[#events][2]=="0")
commands.gquest_reload();now=1;hooks.Think();now=1.3;hooks.Think()
assert(events[#events][1]=="-eject","unassisted path must not refill")
mode=true;callbacks.gquest_reload_assisted()
-- Shutdown releases a pending eject and drops a pending refill.
commands.gquest_reload();hooks.ShutDown();assert(events[#events][1]=="-eject")
local afterShutdown=#events;now=9;hooks.Think();assert(#events==afterShutdown,"shutdown must drop the pending refill")
player.Alive=function() return false end
local count=#events;commands.gquest_reload();assert(#events==count)
print("PASS client reload: native eject pulse/release, delayed own-reserve refill, assisted-off path, shutdown drop, alive gate")

player.Alive=function() return true end
local pressed,changed,active=false,false,true
vr={GetPrimaryHand=function() return 1 end,
 GetActionDigital=function(set,name,hand)
  assert(set=="weapon" and name=="eject" and hand==1)
  return pressed,changed,active
 end}
local function eventCount(name)
 local n=0;for _,e in ipairs(events) do if e[1]==name then n=n+1 end end;return n
end
now=10;hooks.Think()
local ejects=eventCount("+eject");local fills=eventCount("gquest_reload_refill")
pressed=true;changed=true;hooks.Think()
assert(eventCount("+eject")==ejects,"native controller eject duplicated")
now=10.2;hooks.Think();assert(eventCount("gquest_reload_refill")==fills)
now=10.5;hooks.Think();assert(eventCount("gquest_reload_refill")==fills+1)
now=11;hooks.Think();assert(eventCount("gquest_reload_refill")==fills+1,"held button repeats refill")
pressed=false;changed=true;hooks.Think()
pressed=true;hooks.Think()
local other={GetClass=function() return "hlvr_weapon_pistol" end}
player.GetActiveWeapon=function() return other end
now=12;hooks.Think();assert(eventCount("gquest_reload_refill")==fills+1,"weapon switch refilled another weapon")
player.GetActiveWeapon=function() return weapon end
pressed=false;hooks.Think();pressed=true;hooks.Think()
mode=false;callbacks.gquest_reload_assisted();now=13;hooks.Think()
assert(eventCount("gquest_reload_refill")==fills+1,"assistance-off did not cancel transfer")
mode=true;callbacks.gquest_reload_assisted()
pressed=false;hooks.Think();pressed=true;active=false;now=14;hooks.Think();now=15;hooks.Think()
assert(eventCount("gquest_reload_refill")==fills+1,"inactive controller action caused reload")
weapon.GetClass=function() return "hlvr_weapon_crowbar" end
commands.gquest_reload();assert(eventCount("+eject")==ejects,"melee weapon ejected")
print("PASS native reload input: real weapon/eject action, no double eject, one transfer per press, weapon-switch/mode/inactive/melee guards")

weapon.GetClass=function() return "hlvr_weapon_smg1" end
physicalMode=true;callbacks.gquest_reload_physical()
local quick,items,holster
for _,e in ipairs(events) do
 if e[1]=="hlvr_quick_reload" then quick=e[2] end
 if e[1]=="hlvr_hand_items" then items=e[2] end
 if e[1]=="hlvr_ammo_holster_location" then holster=e[2] end
end
assert(quick=="0" and items=="1" and holster=="1","manual mode did not enable native pouch grabs and disable quick reload")
local nativeFills=eventCount("gquest_reload_refill")
commands.gquest_reload();now=16;hooks.Think();now=18;hooks.Think()
assert(eventCount("gquest_reload_refill")==nativeFills,"manual reload automatically filled magazine")
print("PASS manual reload: native hand items and hip pouch enabled, quick reload off, no automatic refill")
