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
dofile("work/gquest-ui/lua/autorun/client/gquest_hand_smoothing.lua")
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
-- Hand smoothing: the button cycles the level, the module takes it and the file keeps it.
assert(GquestHandSmoothing.Enabled and math.abs(GquestHandSmoothing.TAU-0.03)<0.0001,
 "the saved mild level must apply on load")
click("Handglaettung: Mild (klicken zum Wechseln)")
assert(math.abs(GquestHandSmoothing.TAU-0.06)<0.0001,"cycle must reach the module, got "..tostring(GquestHandSmoothing.TAU))
assert(files["gquest_vr_profile.txt"]:find("smooth=strong",1,true),"level must be saved")
click("Handglaettung: Stark (klicken zum Wechseln)")
assert(not GquestHandSmoothing.Enabled,"off must disable the filter")
assert(files["gquest_vr_profile.txt"]:find("smooth=off",1,true),"off must be saved")
-- The frame sizes itself from the content instead of a fixed 680. Asserted with the
-- measurement: the section stack needs more than the old fixed height, so the frame grows to
-- the screen limit, and the usable height (frame minus chrome) is reported for the record.
local frame
for index=#panels,1,-1 do
 if panels[index].kind=="DFrame" and panels[index].valid then frame=panels[index];break end
end
assert(frame and type(frame.ContentHeight)=="number","content height must be reported")
-- The pane is two columns now, so the old "taller than the fixed 680" check would pass for
-- the wrong reason even if a section had fallen off the screen. What matters is that the
-- content fits the reference screen without scrolling: 1104 - 48 - chrome.
local usableOnReferenceScreen = ScrH()-48-GquestUI.SETTINGS_CHROME
assert(frame.ContentHeight<=usableOnReferenceScreen,
    "content must fit the reference screen, got "..tostring(frame.ContentHeight)
    .." against "..tostring(usableOnReferenceScreen))
assert(frame.height==math.min(ScrH()-48,frame.ContentHeight+GquestUI.SETTINGS_CHROME),
 "frame must size to its content, got "..tostring(frame.height))
assert(frame.height>680,"frame must grow past the old fixed 680")
print("GQUEST_UI panel: content="..frame.ContentHeight.."px frame="..frame.height.."px usable="
 ..(frame.height-GquestUI.SETTINGS_CHROME).."px scroll="
 ..math.max(0,frame.ContentHeight-(frame.height-GquestUI.SETTINGS_CHROME)).."px")
print("PASS menu callbacks: root -> alignment -> back -> close -> reopen -> weapons; exact former global-openRoot regression, visibility gate, detection-mismatch adopt button, playspace and smoothing buttons that save and apply, and a frame that sizes itself from the reported content height")
