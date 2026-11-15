-- Boundary harness for the H3VR-style manual weapon mechanics.
-- No engine: a fake player, a fake clip weapon and a fake native magazine drive the real
-- hooks and commands the server module registers.
local hooks, commands, convars = {}, {}, {}
hook = {Add = function(name, _, fn) hooks[name] = fn end}
concommand = {Add = function(name, fn) commands[name] = fn end}
FCVAR_ARCHIVE = 0
function CreateConVar(name, value)
    local entry = {value = value}
    entry.GetBool = function() return entry.value ~= "0" end
    entry.GetFloat = function() return tonumber(entry.value) or 0 end
    entry.GetString = function() return entry.value end
    convars[name] = entry
    return entry
end
function GetConVar(name) return convars[name] end
AddCSLuaFile = function() end
function IsValid(value) return type(value) == "table" end
player = {GetAll = function() return {current} end}
-- The state travels to the panel over one net message; the poll behind it must stay silent in
-- the log, because that log is what the hardware evaluator reads.
util = {AddNetworkString = function(name) sent.networkName = name end}
sent = {}
net = {Start = function(name) sent.name = name end,
       WriteString = function(text) sent.text = text end,
       Send = function(target) sent.player = target end}
local printed = {}
local realPrint = print
print = function(text) printed[#printed + 1] = tostring(text) end

dofile("work/gquest-ui/lua/autorun/server/gquest_weapon_mechanics.lua")

local function clipWeapon(class, clip, maxClip)
    local weapon = {clip = clip}
    weapon.GetClass = function() return class end
    weapon.Clip1 = function() return weapon.clip end
    weapon.SetClip1 = function(_, value) weapon.clip = value end
    weapon.GetMaxClip1 = function() return maxClip end
    weapon.GetPrimaryAmmoType = function() return 4 end
    weapon.SetPrimaryAmmoType = function() return true end
    return weapon
end

local function fakePlayer(weapon, reserve)
    local counts = {[4] = reserve or 0}
    local self = {weapon = weapon, alive = true}
    current = self
    self.IsPlayer = function() return true end
    self.Alive = function() return self.alive end
    self.GetActiveWeapon = function() return self.weapon end
    self.GetAmmoCount = function(_, ammoType) return counts[ammoType] or 0 end
    self.RemoveAmmo = function(_, amount, ammoType) counts[ammoType] = (counts[ammoType] or 0) - amount end
    self.GiveAmmo = function(_, amount, ammoType) counts[ammoType] = (counts[ammoType] or 0) + amount; return amount end
    self.SetAmmo = function(_, amount, ammoType) counts[ammoType] = amount end
    return self
end

local function fire(player_)
    return hooks.EntityFireBullets(player_, {})
end

-- Chamber split: the engine's clip is exactly chamber plus magazine, never more.
local weapon = clipWeapon("weapon_pistol", 18, 18)
local player_ = fakePlayer(weapon, 0)
local state = GquestMech.State(weapon)
assert(state and state.chamber == 1 and state.magazine == 17, "initial split must be one chambered round")
assert(weapon.clip == 18, "the split must not change the total the engine showed")
assert(GquestMech.State(clipWeapon("gmod_camera", 0, 0)) == nil, "unsupported class must have no state")

-- One shot: chamber stays filled by the self-cycling action, the total drops by exactly one.
assert(fire(player_) ~= false, "a chambered pistol must fire")
assert(weapon.clip == 17, "one shot must cost exactly one round")
state = GquestMech.State(weapon)
assert(state.chamber == 1 and state.magazine == 16, "semi-auto must re-chamber from the magazine")

-- Empty chamber clicks instead of borrowing from the magazine.
weapon = clipWeapon("weapon_shotgun", 6, 6)
player_ = fakePlayer(weapon, 0)
assert(fire(player_) ~= false, "chambered shotgun must fire")
state = GquestMech.State(weapon)
assert(state.chamber == 0 and state.magazine == 5, "pump action must leave the chamber empty")
assert(fire(player_) == false, "an empty chamber must not fire, pump or not")
assert(weapon.clip == 5, "a blocked shot must not consume a shell")
commands.gquest_mech_rack(player_)
state = GquestMech.State(weapon)
assert(state.chamber == 1 and state.magazine == 4, "pumping must chamber the next shell")

-- Empty weapon: blocked, slide locked.
weapon = clipWeapon("weapon_smg1", 0, 45)
player_ = fakePlayer(weapon, 0)
assert(fire(player_) == false, "an empty weapon must not fire")
assert(GquestMech.State(weapon).slideLocked, "an empty weapon must lock back")

-- Safety blocks fire and consumes nothing.
weapon = clipWeapon("weapon_pistol", 10, 18)
player_ = fakePlayer(weapon, 0)
commands.gquest_mech_safety(player_)
assert(GquestMech.State(weapon).safety, "safety must engage")
assert(fire(player_) == false, "safety must block the shot")
assert(weapon.clip == 10, "safety must not consume a round")
commands.gquest_mech_safety(player_)
assert(fire(player_) ~= false, "releasing the safety must fire again")

-- Racking a live round ejects it into the player's own reserve: no ammunition is invented.
weapon = clipWeapon("weapon_pistol", 10, 18)
player_ = fakePlayer(weapon, 20)
commands.gquest_mech_rack(player_)
state = GquestMech.State(weapon)
assert(state.chamber == 1 and state.magazine == 8, "racking must chamber the next round")
assert(weapon.clip == 9 and player_:GetAmmoCount(4) == 21, "the ejected round must return to the reserve")

-- Detachable magazine keeps its rounds when dropped.
weapon = clipWeapon("weapon_pistol", 10, 18)
player_ = fakePlayer(weapon, 0)
commands.gquest_mech_mag(player_)
state = GquestMech.State(weapon)
assert(not state.magazineInserted and state.magazine == 0 and state.stored == 9, "the magazine must keep its rounds")
assert(weapon.clip == 1, "a dropped magazine leaves only the chambered round in the gun")
commands.gquest_mech_mag(player_)
state = GquestMech.State(weapon)
assert(state.magazineInserted and state.magazine == 9 and state.chamber == 1, "re-inserting must not chamber a round")
assert(weapon.clip == 10, "re-inserting the same magazine must restore the same total")

-- Fresh magazine comes from the reserve and is capped by what the player owns.
weapon = clipWeapon("weapon_pistol", 0, 18)
player_ = fakePlayer(weapon, 5)
commands.gquest_mech_mag(player_)  -- drop the empty magazine
commands.gquest_mech_mag(player_)  -- insert a fresh one from the reserve
state = GquestMech.State(weapon)
assert(state.magazine == 5 and player_:GetAmmoCount(4) == 0, "a fresh magazine must be capped by the reserve")
assert(state.chamber == 0, "inserting a magazine must never chamber a round")
weapon = clipWeapon("weapon_pistol", 0, 18)
player_ = fakePlayer(weapon, 0)
commands.gquest_mech_mag(player_)
commands.gquest_mech_mag(player_)
assert(not GquestMech.State(weapon).magazineInserted, "an empty reserve must not insert a magazine")

-- Revolver: fires from the cylinder, no chamber step.
weapon = clipWeapon("weapon_357", 6, 6)
player_ = fakePlayer(weapon, 0)
state = GquestMech.State(weapon)
assert(state.chamber == 0 and state.magazine == 6, "a revolver has no separate chamber")
assert(fire(player_) ~= false and weapon.clip == 5, "the revolver must fire from the cylinder")
for _ = 1, 5 do fire(player_) end
assert(weapon.clip == 0 and fire(player_) == false, "the empty revolver must click")

-- One-step reload for the shotgun tops the tube up from the reserve only.
weapon = clipWeapon("weapon_shotgun", 2, 6)
player_ = fakePlayer(weapon, 3)
-- Without the racking step, so the tube is the only thing that changes.
assert(GquestMech.Reload(weapon, GquestMech.Profile("weapon_shotgun"), player_, 4, false))
-- The engine's capacity covers chamber plus tube, so a topped-up shotgun ends at 5, not 7.
assert(weapon.clip == 5 and player_:GetAmmoCount(4) == 0, "the tube must fill up to the capacity the engine reports")

-- Native HLVR magazine: only the linked magazine is written, and a refused write drops the
-- local state instead of leaving the model ahead of the engine.
local function nativeWeapon(count, capacity, failWrite, chamberField)
    local weapon_ = {clip = 10}
    weapon_.GetClass = function() return "hlvr_weapon_smg1" end
    weapon_.Clip1 = function() return weapon_.clip end
    weapon_.SetClip1 = function(_, value) weapon_.clip = value end
    weapon_.GetMaxClip1 = function() return 45 end
    weapon_.GetPrimaryAmmoType = function() return 4 end
    local magazine = {}
    local data = {m_iCurrentAmmoCount = count, m_iMaxAmmoCount = capacity, m_hLoadedWeapon = weapon_}
    local saved = {m_hLoadedMagazine = magazine, m_iChamberedRounds = chamberField or 1}
    weapon_.GetSaveTable = function() return saved end
    magazine.GetSaveTable = function() return data end
    magazine.SetSaveValue = function(_, key, value)
        if failWrite then
            failWrite = false
            return false
        end
        if key == "m_iChamberedRounds" then saved.m_iChamberedRounds = value else data[key] = value end
        return true
    end
    return weapon_, data, saved
end

weapon, data, saved = nativeWeapon(45, 45, false)
player_ = fakePlayer(weapon, 0)
state = GquestMech.State(weapon)
assert(state and state.chamber == 1 and state.magazine == 44, "native magazine must split chamber plus rounds")
assert(fire(player_) ~= false, "a native weapon must still fire")
assert(data.m_iCurrentAmmoCount == 43 and saved.m_iChamberedRounds == 1,
    "the native write must not touch the chamber field while that convar is off")
assert(weapon.clip == 10, "the native path must not write the unrelated base clip")

weapon, data = nativeWeapon(3, 45, true)
player_ = fakePlayer(weapon, 0)
assert(fire(player_) ~= false, "a refused write must not block the shot")
assert(data.m_iCurrentAmmoCount == 3, "a refused write must leave the engine untouched")
-- State() re-reads a dropped state, so the next model starts from the engine again instead of
-- continuing from a lie: a fresh split of the unchanged magazine (3) is what comes back.
state = GquestMech.State(weapon)
assert(state.chamber + state.magazine == 3, "a refused write must resync from the engine")

weapon, data = nativeWeapon(45, 0, false)
assert(GquestMech.State(weapon) == nil, "an invalid native capacity must leave the weapon alone")

-- Resync: an engine change behind our back drops the model instead of overwriting the engine.
weapon = clipWeapon("weapon_pistol", 12, 18)
player_ = fakePlayer(weapon, 0)
state = GquestMech.State(weapon)
weapon.clip = 3
hooks.Think()
assert(GquestMech.State(weapon).chamber + GquestMech.State(weapon).magazine == 3,
    "the resync must re-read the engine clip, not invent one")

-- Disabled means inert: the hook may not touch a shot.
convars.gquest_mech_enabled.value = "0"
weapon = clipWeapon("weapon_pistol", 0, 18)
player_ = fakePlayer(weapon, 0)
assert(hooks.EntityFireBullets(player_, {}) == nil, "a disabled module must not block shots")
convars.gquest_mech_enabled.value = "1"

-- The weapon panel gets the same numbers over the wire, and a poll may not add a log line.
player_ = fakePlayer(clipWeapon("weapon_pistol", 12, 18), 0)
commands.gquest_mech_poll(player_)  -- first poll may initialise the state and log that once
local before = #printed
commands.gquest_mech_poll(player_)
assert(sent.networkName == "GquestMechState", "the state channel must be registered")
assert(sent.name == "GquestMechState", "the poll must send the state message")
assert(sent.player == player_, "the poll must answer only the player who asked")
assert(string.find(sent.text, "class=weapon_pistol", 1, true), "payload must name the weapon")
assert(string.find(sent.text, "chamber=1", 1, true), "payload must carry the chamber")
assert(string.find(sent.text, "mag=11", 1, true), "payload must carry the magazine")
assert(#printed == before, "a poll must not write a log line")
commands.gquest_mech_state(player_)
assert(sent.name == "GquestMechState" and string.find(sent.text, "capacity=18", 1, true),
    "the state command must also feed the panel")
-- A missing state is explained, not left blank: the panel must be able to name the weapon
-- and the reason, so "nothing is displayed" is never all the headset shows.
local unarmed = {IsPlayer = function() return true end, Alive = function() return true end,
    GetActiveWeapon = function() return nil end}
before = #printed
commands.gquest_mech_poll(unarmed)
assert(sent.player == unarmed, "the poll must answer only the player who asked")
assert(string.find(sent.text, "reason=nohand", 1, true), "empty hands must be reported, got " .. tostring(sent.text))
assert(#printed == before, "a poll must not write a log line, not even for an empty hand")
commands.gquest_mech_poll(fakePlayer(clipWeapon("weapon_crowbar", 0, 0), 0))
assert(string.find(sent.text, "reason=unsupported", 1, true)
    and string.find(sent.text, "class=weapon_crowbar", 1, true),
    "a weapon without a profile must be named as unsupported, got " .. tostring(sent.text))
commands.gquest_mech_poll(fakePlayer(clipWeapon("weapon_ar2", 30, 0), 0))
assert(string.find(sent.text, "reason=engine", 1, true)
    and string.find(sent.text, "class=weapon_ar2", 1, true)
    and string.find(sent.text, "code=weapon_has_no_magazine", 1, true),
    "an unreadable engine value must carry its reason code, got " .. tostring(sent.text))
-- A reason text with spaces would break the panel's parser, so every field stays key=value.
for token in string.gmatch(sent.text, "%S+") do
    assert(string.find(token, "=", 1, true), "every field must be key=value, stray: " .. token)
end
local dead = {IsPlayer = function() return true end, Alive = function() return false end,
    GetActiveWeapon = function() return nil end}
commands.gquest_mech_poll(dead)
assert(string.find(sent.text, "reason=dead", 1, true), "a dead player must be reported")

-- The panel follows the hand: another weapon is pushed as soon as it is active, so picking one
-- in the menu does not wait for the next poll. Holding the same weapon sends nothing.
local pushes = 0
local writeString = net.WriteString
net.WriteString = function(text) pushes = pushes + 1; writeString(text) end
local watched = fakePlayer(clipWeapon("weapon_pistol", 18, 18), 0)
hooks.Think()
assert(pushes == 1 and sent.player == watched, "a newly held weapon must be pushed at once")
local pushed = sent.text
assert(string.find(pushed, "class=weapon_pistol", 1, true) and string.find(pushed, "chamber=1", 1, true),
    "the pushed state must be the full state, got " .. tostring(pushed))
commands.gquest_mech_poll(watched)
assert(sent.text == pushed, "push and poll must describe the same weapon the same way")
pushes = 0
hooks.Think()
assert(pushes == 0, "holding the same weapon must not send anything")
before = #printed
fakePlayer(clipWeapon("weapon_crowbar", 0, 0), 0)
hooks.Think()
assert(pushes == 1, "switching the weapon must push exactly once")
assert(string.find(sent.text, "reason=unsupported", 1, true)
    and string.find(sent.text, "class=weapon_crowbar", 1, true),
    "the switch must push the same explanation the poll gives, got " .. tostring(sent.text))
assert(#printed == before, "a weapon switch must not write a log line")
net.WriteString = writeString

realPrint("PASS weapon mechanics: chamber split, auto cycle, empty-chamber click, slide lock, safety, "
    .. "live-round ejection to reserve, retaining magazine, reserve cap, no free chambering, "
    .. "revolver cylinder, pump action, tube reload, native magazine write, write rollback, "
    .. "resync, disabled gate, a silent state poll that explains a missing state and a weapon "
    .. "switch pushed to the panel without waiting for a poll")
