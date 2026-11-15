local panels,commands,selected={},{},{}
GquestWeapons=nil
function IsValid(v) return type(v)=="table" and not rawget(v,"closed") end
function ScrW() return 1200 end;function ScrH() return 1000 end
TOP=1;BOTTOM=2;FILL=3;LEFT=4
local methods={}
setmetatable(methods,{__index=function() return function() end end})
function methods:SetText(s) self.text=s end
function methods:Close() self.closed=true end
function methods:IsVisible() return not rawget(self,"closed") end
vgui={Create=function(kind,parent) local p=setmetatable({kind=kind,parent=parent},{__index=methods});panels[#panels+1]=p;return p end}
gui={HideGameUI=function() end}
concommand={Add=function(k,fn) commands[k]=fn end}
function RunConsoleCommand(cmd,arg) selected[#selected+1]={cmd,arg} end
-- The live state comes over the wire and is polled on a timer.
local receivers,nextPayload,timers={},"none",{}
net={Receive=function(name,fn) receivers[name]=fn end,
     ReadString=function() return nextPayload end}
timer={Create=function(name,rate,reps,fn) timers[name]=fn end,
       Remove=function(name) timers[name]=nil end}
assert(loadfile("work/gquest-ui/lua/autorun/client/gquest_weapon_catalog.lua"))()
-- The mechanics buttons are not weapon selections and must not be counted as such.
local mechanics={{"Magazin","gquest_mech_mag"},{"Durchladen","gquest_mech_rack"},
 {"Nachladen","gquest_mech_reload"},{"Sicherung","gquest_mech_safety"},
 {"Zustand","gquest_mech_state"},{"Haende","gquest_hands_state"}}
local isMechanic={}
for _,entry in ipairs(mechanics) do isMechanic[entry[1]]=true end
commands.gquest_weapons();assert(GquestWeapons.IsMenuVisible())
local count=0
for _,p in ipairs(panels) do
 if p.kind=="DButton" and not isMechanic[p.text] and p.text~="Zurueck zum Spiel" and p.text~="Nachladen / HL2-Magazin auswerfen" then
  count=count+1;p.DoClick();local last=selected[#selected]
  assert(last[1]=="gquest_hl2_equip" and string.sub(last[2],1,7)=="weapon_")
 end
 assert(not string.find(rawget(p,"text") or "","ArcVR",1,true))
end
assert(count==11,"HL2 plus Physgun roster")
-- The click is answered before the server is: the line names what is being equipped, and the
-- panel closes once that weapon is confirmed instead of on the click itself.
assert(GquestWeapons.IsMenuVisible(),"the panel must stay open until the pick is confirmed")
local function live()
 for i=#panels,1,-1 do
  local p=panels[i]
  if p.kind=="DLabel" and type(p.text)=="string" and string.sub(p.text,1,6)=="Waffe:" then return p end
 end
end
assert(live().text:find("wird ausgeruestet",1,true),"the line must show the pending pick, got "..tostring(live().text))
assert(timers.GquestMechPending,"a pick needs a fallback close if the server never answers")
nextPayload="class=weapon_pistol kind=magazine chamber=1 mag=17 capacity=18 safety=false slide=false inserted=true"
receivers.GquestMechState()
assert(live().text:find("wird ausgeruestet",1,true),"an answer about the old gun must not replace the pending pick")
nextPayload="state=none reason=unsupported class=weapon_physgun code=none"
receivers.GquestMechState()
assert(not live().text:find("wird ausgeruestet",1,true),"the confirmed pick must replace the pending line")
assert(timers.GquestMechClose,"the panel must close after the confirmation")
timers.GquestMechClose()
assert(not GquestWeapons.IsMenuVisible(),"the panel must close once the pick is confirmed")
-- A headset has no keyboard: every mechanics command from docs/UPDATE-CHECKLISTE.md is one
-- click, and the panel stays open so several actions in a row need no reopened menu.
commands.gquest_weapons();assert(GquestWeapons.IsMenuVisible())
for _,entry in ipairs(mechanics) do
 local found
 for _,p in ipairs(panels) do
  if p.kind=="DButton" and p.text==entry[1] then found=p end
 end
 assert(found,"missing mechanics button "..entry[1])
 found.DoClick()
 local last=selected[#selected]
 assert(last[1]==entry[2],"button "..entry[1].." must issue "..entry[2]..", got "..tostring(last[1]))
 assert(GquestWeapons.IsMenuVisible(),"mechanics button "..entry[1].." must keep the panel open")
end
-- The panel shows the server's chamber and magazine numbers instead of only logging them.
assert(receivers.GquestMechState,"the catalog must listen for the state message")
local function issued(name)
 for i=#selected,1,-1 do if selected[i][1]==name then return true end end
 return false
end
assert(issued("gquest_mech_poll"),"opening the panel must ask for the state once")
assert(live(),"the panel must carry a state line")
nextPayload="class=weapon_pistol kind=magazine chamber=1 mag=17 capacity=18 safety=false slide=false inserted=true"
receivers.GquestMechState()
assert(live().text:find("Kammer 1",1,true),"state line must show the chamber, got "..tostring(live().text))
assert(live().text:find("Magazin 17/18",1,true),"state line must show magazine and capacity")
assert(live().text:find("Sicherung aus",1,true),"state line must show the safety")
nextPayload="class=weapon_pistol kind=magazine chamber=0 mag=0 capacity=18 safety=true slide=true inserted=false"
receivers.GquestMechState()
assert(live().text:find("Sicherung an",1,true) and live().text:find("Verschluss offen",1,true)
 and live().text:find("Magazin draussen",1,true),"state line must follow the second state, got "..tostring(live().text))
-- An empty line is a result: every case names the weapon and the reason.
nextPayload="state=none reason=nohand class=none code=none"
receivers.GquestMechState()
assert(live().text:find("nichts in der Hand",1,true),"empty hands must be named, got "..tostring(live().text))
nextPayload="state=none reason=dead class=none code=none"
receivers.GquestMechState()
assert(live().text:find("Spieler tot",1,true),"a dead player must be named, got "..tostring(live().text))
nextPayload="state=none reason=unsupported class=weapon_crowbar code=none"
receivers.GquestMechState()
assert(live().text:find("Brechstange",1,true) and live().text:find("weapon_crowbar",1,true)
 and live().text:find("hat keine Mechanik",1,true),"an unsupported weapon must be named, got "..tostring(live().text))
nextPayload="state=none reason=engine class=hlvr_pistol code=weapon_has_no_clip"
receivers.GquestMechState()
assert(live().text:find("Pistole",1,true) and live().text:find("hlvr_pistol",1,true)
 and live().text:find("kein Magazin am Modell",1,true),"an unreadable engine value must say why, got "..tostring(live().text))
nextPayload="none"
receivers.GquestMechState()
assert(live().text:find("keine mit Mechanik",1,true),"an old server without a reason must still say something")
assert(timers.GquestMechPoll,"a poll timer must run while the panel is open")
timers.GquestMechPoll()
assert(timers.GquestMechPoll,"the poll must keep running while the panel is open")
for i=#panels,1,-1 do
 local p=panels[i]
 if p.kind=="DButton" and p.text=="Zurueck zum Spiel" then p.DoClick() break end
end
assert(not GquestWeapons.IsMenuVisible(),"closing the panel must close it")
timers.GquestMechPoll()
assert(timers.GquestMechPoll==nil,"the poll must stop with the panel")
print("PASS HL2-only catalog: eleven real weapon selections, no ArcVR control, a selection "
 .."shows the pending pick and closes the tracked menu once confirmed, six mechanics buttons that issue their command without closing the panel, "
 .."a live chamber/magazine line fed by the server state, and a reason naming the weapon "
 .."whenever that line has no numbers")
