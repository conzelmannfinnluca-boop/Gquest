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
file={Read=function(path) return files[path] end,Write=function(path,_,text) files[path]=text end}
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
print("PASS menu callbacks: root -> alignment -> back -> close -> reopen -> weapons; exact former global-openRoot regression, visibility gate and detection-mismatch adopt button")
