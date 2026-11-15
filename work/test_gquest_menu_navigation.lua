local commands,panels={},{}
local methods={}
function methods:SetText(text) self.text=text end
function methods:SetTitle(title) self.title=title end
function methods:SetSize(w,h) self.width=w;self.height=h end
function methods:GetWide() return self.width or 660 end
function methods:IsVisible() return self.valid~=false end
function methods:Close() self.valid=false end
function methods:Add(kind) return vgui.Create(kind,self) end
local function create(kind,parent)
 local panel=setmetatable({kind=kind,parent=parent,valid=true},{__index=function(_,key) return methods[key] or function() end end})
 panels[#panels+1]=panel;return panel
end
vgui={Create=create}
local files={}
-- Garry's Mod's signature is file.Write(name, contents); the third parameter this stub
-- used to take meant every real two-argument call stored nil, so nothing saved could be
-- asserted on. Fixed to the signature the game actually uses.
file={Read=function(path) return files[path] end,Write=function(path,text) files[path]=text end}
concommand={Add=function(name,fn) commands[name]=fn end}
hook={Add=function() end}
timer={Simple=function(_,fn) fn() end}
gui={HideGameUI=function() end}
function IsValid(v) return type(v)=="table" and v.valid~=false end
function RealTime() return 0 end
function ScrW() return 1032 end
function ScrH() return 1104 end
function Color() return {} end
local console={}
function RunConsoleCommand(name,...) console[#console+1]={name,...} end
notification={AddLegacy=function() end}
GQUEST_WEAPON_ALIGN={BuildPanel=function(parent) return create("DPanel",parent) end}
-- The menu reads its profiles from the shared module, as it does in game.
dofile("work/gquest-ui/lua/autorun/client/gquest_vr_profiles.lua")
dofile("work/gquest-ui/lua/autorun/client/gquest_playspace.lua")
dofile("work/gquest-ui/lua/autorun/client/gquest_vr_ui.lua")
local function click(text)
 for i=#panels,1,-1 do local p=panels[i];if p.text==text and p.valid then assert(type(p.DoClick)=="function");p.DoClick();return end end
 error("missing button "..text)
end
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
click("Waffe ausrichten");assert(GquestUI.IsMenuVisible())
-- Executes the callback that previously called a nonexistent global openRoot.
click("Zurueck");assert(GquestUI.IsMenuVisible())
click("Zurueck zum Spiel");assert(not GquestUI.IsMenuVisible())
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
click("Waffen");assert(not GquestUI.IsMenuVisible())
-- A detection mismatch must offer a one-click way onto the detected device. The mock
-- reports a Quest 3S while the profile is still a Quest 3 one.
files["gquest_device.txt"]="quest3s\n"
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
click("Auf Quest 3S umstellen (Empfehlung)")
local applied
for _,entry in ipairs(console) do
 if entry[1]=="vr_eye_resolution" then applied=entry[2] end
end
assert(applied=="1374x1440","adopt button must apply the 3S recommendation, got "..tostring(applied))
-- Playspace controls: the step button cycles the profile's list and reaches the turn
-- module at once, the stance button toggles and only stores.
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
assert(GquestPlayspace.STEP==30,"a saved step must apply on load")
click("Snap-Turn: 30 Grad (klicken zum Wechseln)")
assert(GquestPlayspace.STEP==45,"cycle must reach the turn module, got "..tostring(GquestPlayspace.STEP))
assert(files["gquest_vr_profile.txt"]:find("snap=45",1,true),"step must be saved")
click("Fortbewegung: Stehend")
assert(files["gquest_vr_profile.txt"]:find("stance=seated",1,true),"stance must be saved")
click("Fortbewegung: Sitzend")
assert(files["gquest_vr_profile.txt"]:find("stance=stand",1,true),"stance must toggle back")
print("PASS menu callbacks: root -> alignment -> back -> close -> reopen -> weapons; exact former global-openRoot regression, visibility gate, detection-mismatch adopt button, and playspace step/stance buttons that save and apply")
