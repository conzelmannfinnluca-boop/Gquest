-- GQuest: manual (H3VR-style) weapon mechanics, server side.
--
-- The retail HL2 path treats a gun as "clip number goes down". H3VR-style handling needs a
-- round in the chamber, a magazine that keeps its own rounds, a safety, a slide that locks
-- back on empty and a racking step that is not the same as reloading.
--
-- This file owns exactly that model. It does not invent ammunition: chamber + magazine is
-- always the number the engine already shows as the clip, so the totals cannot drift, and a
-- round that is racked out of a loaded chamber goes back into the player's own reserve.
--
-- Firing is intercepted with EntityFireBullets. If the engine never calls that hook for a
-- weapon (the native HLVR path may not), nothing is blocked and nothing changes - the failure
-- mode is "retail behaviour", not "gun stops working".
--
-- Every transition is validated and logged as GQUEST_MECH so a headset log shows the state
-- that actually reached the weapon instead of what the code hoped for.
-- Server only, and deliberately not sent to clients: the state machine writes to entities.
-- The gesture layer keeps its own short class list instead of shipping this file to the
-- headset.
GquestMech = GquestMech or {}

local ENABLED_CVAR = "gquest_mech_enabled"
local WRITE_CHAMBER_CVAR = "gquest_mech_write_chamber"

-- action: how the weapon gets the next round into the chamber
--   auto  - cycles itself (pistol, SMG, AR2)
--   pump  - needs a pump between shots (shotgun)
--   bolt  - needs a manual bolt (crossbow)
--   none  - no separate chamber step (revolver fires from the cylinder, RPG is single-shot)
local PROFILES = {
    weapon_pistol = {kind = "magazine", capacity = 18, action = "auto", chambered = true, safety = true},
    weapon_357 = {kind = "revolver", capacity = 6, action = "none", chambered = false, safety = false},
    weapon_smg1 = {kind = "magazine", capacity = 45, action = "auto", chambered = true, safety = true},
    weapon_ar2 = {kind = "magazine", capacity = 30, action = "auto", chambered = true, safety = true},
    weapon_shotgun = {kind = "shells", capacity = 6, action = "pump", chambered = true, safety = false},
    weapon_crossbow = {kind = "single", capacity = 1, action = "bolt", chambered = true, safety = false},
    weapon_rpg = {kind = "single", capacity = 1, action = "none", chambered = true, safety = true},
}

local STATES_NET = "GquestMechState"
util.AddNetworkString(STATES_NET)

local states = setmetatable({}, {__mode = "k"})

local function finite(value)
    return type(value) == "number" and value == value and value >= -1000000 and value <= 1000000
end

local function whole(value)
    return finite(value) and value >= 0 and value <= 100000 and value == math.floor(value)
end

local function enabled()
    local convar = GetConVar(ENABLED_CVAR)
    return not convar or convar:GetBool()
end

local function baseClass(class)
    if type(class) ~= "string" then return nil end
    if string.sub(class, 1, 5) == "hlvr_" then return string.sub(class, 6) end
    return class
end

function GquestMech.Profile(class)
    return PROFILES[baseClass(class) or ""]
end

--- The native HLVR weapons keep the loaded magazine as its own entity. Only a magazine that
--- belongs to this weapon may be touched, and only if it can report its state.
local function nativeMagazine(weapon)
    if type(weapon.GetSaveTable) ~= "function" then return nil end
    local saved = weapon:GetSaveTable()
    local magazine = saved and saved.m_hLoadedMagazine
    if not IsValid(magazine) or type(magazine.GetSaveTable) ~= "function" then return nil end
    local data = magazine:GetSaveTable()
    if type(data) ~= "table" or data.m_hLoadedWeapon ~= weapon then return nil end
    if type(magazine.SetSaveValue) ~= "function" then return nil end
    return {magazine = magazine, data = data, saved = saved}
end

local function bindingFor(weapon)
    local native = nativeMagazine(weapon)
    if native then
        local capacity = native.data.m_iMaxAmmoCount
        if not whole(capacity) or capacity < 1 or capacity > 1024 then return nil, "native capacity invalid" end
        return {
            native = true,
            capacity = capacity,
            readTotal = function()
                local count = native.data.m_iCurrentAmmoCount
                if not whole(count) or count > capacity then return nil end
                return count
            end,
            write = function(chamber, magazine)
                local magazineOk = native.data.m_iCurrentAmmoCount
                local chamberOk = native.saved.m_iChamberedRounds
                local wantMagazine = math.min(magazine, capacity)
                local writtenMagazine = native.magazine:SetSaveValue("m_iCurrentAmmoCount", wantMagazine)
                local after = native.magazine:GetSaveTable()
                if writtenMagazine ~= true or not after or after.m_iCurrentAmmoCount ~= wantMagazine then
                    native.magazine:SetSaveValue("m_iCurrentAmmoCount", magazineOk)
                    return false, "native magazine write failed"
                end
                -- The chamber is written only when asked for: the native insertion/racking
                -- animation owns it on this build, and two writers would fight over it.
                local convar = GetConVar(WRITE_CHAMBER_CVAR)
                if convar and convar:GetBool() then
                    native.magazine:SetSaveValue("m_iChamberedRounds", 0)
                    native.saved.m_iChamberedRounds = chamber
                    local check = weapon:GetSaveTable()
                    if not check or check.m_iChamberedRounds ~= chamber then
                        if chamberOk ~= nil then native.saved.m_iChamberedRounds = chamberOk end
                        return true, "chamber write refused"
                    end
                end
                return true
            end,
            describe = function()
                return string.format("native mag=%s chamber=%s",
                    tostring(native.data.m_iCurrentAmmoCount), tostring(native.saved.m_iChamberedRounds))
            end,
        }, nil
    end
    if type(weapon.Clip1) ~= "function" or type(weapon.SetClip1) ~= "function" then
        return nil, "weapon has no clip"
    end
    local maxClip = weapon.GetMaxClip1 and weapon:GetMaxClip1() or -1
    if not whole(maxClip) or maxClip < 1 then return nil, "weapon has no magazine" end
    local capacity = math.min(maxClip, 1024)
    return {
        native = false,
        capacity = capacity,
        readTotal = function()
            local clip = weapon:Clip1()
            if not whole(clip) then return nil end
            return clip
        end,
        write = function(chamber, magazine)
            local total = chamber + magazine
            if total > capacity then total = capacity end
            weapon:SetClip1(total)
            if weapon:Clip1() ~= total then return false, "clip write failed" end
            return true
        end,
        describe = function()
            return string.format("clip=%d", weapon:Clip1())
        end,
    }, nil
end

--- Split the engine's clip into chamber + magazine once, so the sum stays exactly what the
--- engine already had. Returns nil when the engine state cannot be read - then the weapon is
--- left completely alone.
local function stateFor(weapon, profile)
    local state = states[weapon]
    if state then return state end
    local binding, reason = bindingFor(weapon)
    if not binding then return nil, reason end
    local total = binding.readTotal()
    if not whole(total) then return nil, "clip unreadable" end
    local chamber = (profile.chambered and total > 0) and 1 or 0
    state = {
        weapon = weapon,
        profile = profile,
        binding = binding,
        chamber = chamber,
        magazine = math.min(total - chamber, binding.capacity),
        safety = false,
        slideLocked = false,
        magazineInserted = true,
        stored = 0,
        ready = true,
    }
    states[weapon] = state
    GquestMech.Log(state, "init")
    return state
end

function GquestMech.Log(state, action, note)
    if not state then return end
    local total = state.chamber + state.magazine
    print(string.format("GQUEST_MECH action=%s class=%s chamber=%d mag=%d total=%d safety=%s slide=%s inserted=%s stored=%d%s",
        action, state.weapon:GetClass(), state.chamber, state.magazine, total,
        tostring(state.safety), tostring(state.slideLocked), tostring(state.magazineInserted),
        state.stored, note and (" note=" .. note) or ""))
end

--- Push the model back into the engine. A refused write drops the whole weapon's state so the
--- next shot re-reads the engine instead of continuing from a lie.
local function commit(state, action, note)
    local ok, reason = state.binding.write(state.chamber, state.magazine)
    if not ok then
        states[state.weapon] = nil
        print(string.format("GQUEST_MECH write refused class=%s reason=%s", state.weapon:GetClass(), tostring(reason)))
        return false
    end
    if reason then note = note and (note .. " " .. reason) or reason end
    GquestMech.Log(state, action, note)
    return true
end

local function reserveType(weapon)
    local ammoType = weapon.GetPrimaryAmmoType and weapon:GetPrimaryAmmoType()
    return whole(ammoType) and ammoType or nil
end

local function reserveCount(player, owner_, ammoType)
    if not ammoType or not player or type(player.GetAmmoCount) ~= "function" then return nil end
    local count = player:GetAmmoCount(ammoType)
    return whole(count) and count or nil
end

local function regularWeapon(player)
    if not IsValid(player) or not player:Alive() then return nil end
    local weapon = player.GetActiveWeapon and player:GetActiveWeapon()
    if not IsValid(weapon) then return nil end
    local profile = GquestMech.Profile(weapon:GetClass())
    if not profile then return nil end
    return weapon, profile
end

--- One shot. Returns true when the engine may fire.
local function consumeShot(state, profile)
    if state.safety then
        GquestMech.Log(state, "blocked", "safety")
        return false
    end
    if profile.kind == "revolver" then
        if state.magazine <= 0 then
            state.slideLocked = true
            GquestMech.Log(state, "blocked", "empty")
            return false
        end
        state.magazine = state.magazine - 1
    elseif profile.chambered and state.chamber <= 0 then
        -- A chamber that is empty clicks. It never quietly borrows a round from the magazine:
        -- that is exactly the difference between this and the retail clip model.
        state.slideLocked = state.magazine <= 0
        GquestMech.Log(state, "blocked", "not chambered")
        return false
    elseif state.chamber <= 0 and state.magazine <= 0 then
        state.slideLocked = true
        GquestMech.Log(state, "blocked", "empty")
        return false
    else
        state.chamber = 0
        if profile.action == "auto" and state.magazine > 0 then
            state.magazine = state.magazine - 1
            state.chamber = 1
            state.slideLocked = false
        elseif profile.action == "auto" then
            state.slideLocked = true
        else
            state.slideLocked = state.magazine <= 0
        end
    end
    return true
end

function GquestMech.Fire(weapon, profile)
    local state = stateFor(weapon, profile)
    if not state then return true, "no state" end
    local allowed = consumeShot(state, profile)
    if not commit(state, allowed and "fire" or "fire-blocked") then return true, "write refused" end
    return allowed
end

--- Rack / pump / bolt. A live round in the chamber is ejected into the player's own reserve,
--- which is what H3VR does and what keeps the totals honest.
function GquestMech.Rack(weapon, profile, player, ammoType)
    local state = stateFor(weapon, profile)
    if not state then return false end
    if profile.action == "none" then
        GquestMech.Log(state, "rack", "weapon has no racking step")
        return false
    end
    if state.chamber > 0 then
        state.chamber = 0
        if player and ammoType and type(player.GiveAmmo) == "function" then
            player:GiveAmmo(1, ammoType, true)
        end
    end
    if state.magazine > 0 then
        state.magazine = state.magazine - 1
        state.chamber = 1
        state.slideLocked = false
    else
        state.chamber = 0
        state.slideLocked = true
    end
    return commit(state, "rack")
end

--- Drop the magazine. It keeps the rounds that are still in it, so re-inserting it is not free.
function GquestMech.MagazineOut(weapon, profile)
    local state = stateFor(weapon, profile)
    if not state then return false end
    if profile.kind ~= "magazine" then
        GquestMech.Log(state, "mag-out", "no detachable magazine")
        return false
    end
    if not state.magazineInserted then
        GquestMech.Log(state, "mag-out", "already out")
        return false
    end
    state.stored = state.magazine
    state.magazine = 0
    state.magazineInserted = false
    state.slideLocked = true
    return commit(state, "mag-out")
end

--- Insert a magazine: the one that was dropped if it still holds rounds, else a fresh one from
--- the player's reserve. Inserting never chambers a round - that is the racking step.
function GquestMech.MagazineIn(weapon, profile, player, ammoType)
    local state = stateFor(weapon, profile)
    if not state then return false end
    if profile.kind ~= "magazine" then
        GquestMech.Log(state, "mag-in", "no detachable magazine")
        return false
    end
    if state.magazineInserted then
        GquestMech.Log(state, "mag-in", "already inserted")
        return false
    end
    local rounds = state.stored
    if rounds <= 0 then
        local reserve = reserveCount(player, nil, ammoType)
        if not reserve then
            GquestMech.Log(state, "mag-in", "reserve unreadable")
            return false
        end
        rounds = math.min(state.binding.capacity, reserve)
        if rounds <= 0 then
            GquestMech.Log(state, "mag-in", "no reserve")
            return false
        end
        player:RemoveAmmo(rounds, ammoType)
        local after = reserveCount(player, nil, ammoType)
        if after ~= reserve - rounds then
            if type(player.SetAmmo) == "function" then player:SetAmmo(reserve, ammoType) end
            print("GQUEST_MECH write refused reason=reserve transfer failed")
            return false
        end
    end
    state.magazine = math.min(rounds, state.binding.capacity)
    state.stored = 0
    state.magazineInserted = true
    return commit(state, "mag-in")
end

function GquestMech.Safety(weapon, profile, value)
    local state = stateFor(weapon, profile)
    if not state then return false end
    if not profile.safety then
        GquestMech.Log(state, "safety", "weapon has no safety")
        return false
    end
    state.safety = value == nil and not state.safety or value and true or false
    return commit(state, "safety")
end

--- Reload in one step (magazine out, magazine in, optional rack).
function GquestMech.Reload(weapon, profile, player, ammoType, rack)
    local state = stateFor(weapon, profile)
    if not state then return false end
    if profile.kind == "magazine" then
        GquestMech.MagazineOut(weapon, profile)
        GquestMech.MagazineIn(weapon, profile, player, ammoType)
    elseif profile.kind == "shells" then
        local reserve = reserveCount(player, nil, ammoType)
        if not reserve then return false end
        -- The engine's capacity covers the whole gun, so the chambered shell counts against it.
        local missing = math.min(state.binding.capacity - (state.chamber + state.magazine), reserve)
        if missing <= 0 then
            GquestMech.Log(state, "reload", "full or no reserve")
            return false
        end
        player:RemoveAmmo(missing, ammoType)
        state.magazine = state.magazine + missing
    else
        if state.magazine > 0 or state.chamber > 0 then
            GquestMech.Log(state, "reload", "already loaded")
            return false
        end
        local reserve = reserveCount(player, nil, ammoType)
        if not reserve or reserve <= 0 then return false end
        player:RemoveAmmo(1, ammoType)
        if profile.chambered then state.chamber = 1 else state.magazine = 1 end
    end
    if rack then GquestMech.Rack(weapon, profile, player, ammoType) end
    return commit(state, "reload")
end

function GquestMech.State(weapon)
    local profile = GquestMech.Profile(weapon and weapon:GetClass())
    if not profile then return nil end
    return stateFor(weapon, profile)
end

-- Firing gate. Returning false stops the engine's shot; anything unexpected returns true so a
-- broken state can never turn a working gun into a dead one.
hook.Add("EntityFireBullets", "GquestMechFire", function(entity, _)
    if not enabled() then return end
    local player = IsValid(entity) and entity.IsPlayer and entity:IsPlayer() and entity or nil
    if not player then return end
    local weapon, profile = regularWeapon(player)
    if not weapon or not profile then return end
    local allowed = GquestMech.Fire(weapon, profile)
    if allowed == false then return false end
end)

-- Assigned once the panel section below exists; the think hook runs long after that.
local watchHand

-- Keep the model in step when the engine changes the clip behind our back (native insertion,
-- pickup, admin command). A mismatch drops the local state, it never "corrects" the engine.
-- The same pass lets the panel follow the hand: a new active weapon is pushed at once, so
-- picking one in the menu does not wait for the next poll.
hook.Add("Think", "GquestMechResync", function()
    local active = enabled()
    for _, player in ipairs(player.GetAll and player.GetAll() or {}) do
        if watchHand then watchHand(player) end
        if active then
            local weapon, profile = regularWeapon(player)
            if weapon and profile and states[weapon] then
                local total = states[weapon].binding.readTotal()
                if total == nil or total ~= states[weapon].chamber + states[weapon].magazine then
                    states[weapon] = nil
                end
            end
        end
    end
end)

local function commandWeapon(player)
    local weapon, profile = regularWeapon(player)
    if not weapon then return nil end
    return weapon, profile, player, reserveType(weapon)
end

--- The state lives on the server; the weapon panel runs on the client. One flat line is enough
--- to draw it, and it is the same numbers the log shows.
local function statePayload(weapon, profile, state)
    return string.format("class=%s kind=%s chamber=%d mag=%d capacity=%d safety=%s slide=%s inserted=%s",
        weapon:GetClass(), profile.kind, state.chamber, state.magazine, state.binding.capacity,
        tostring(state.safety), tostring(state.slideLocked), tostring(state.magazineInserted))
end

local function pushState(player, text)
    if not IsValid(player) or not net or not net.Start then return end
    net.Start(STATES_NET)
    net.WriteString(text)
    net.Send(player)
end

--- Nothing to draw is a result too: the panel names the weapon and the reason, so an empty
--- line can be checked against what is actually in the hand. Codes stay one token each, and
--- the engine's own reason text is flattened to underscores.
local function emptyPayload(reason, class, code)
    if code then code = string.gsub(tostring(code), "%s+", "_") end
    return string.format("state=none reason=%s class=%s code=%s",
        reason, class or "none", code or "none")
end

--- Either the state, or the reason it is missing. The active weapon is read here directly:
--- the mechanic only accepts a profile, but the panel must also be able to say "this weapon
--- has no mechanic" instead of showing nothing.
local function pollPayload(player)
    if not IsValid(player) then return emptyPayload("dead") end
    if type(player.Alive) == "function" and not player:Alive() then return emptyPayload("dead") end
    local weapon = player.GetActiveWeapon and player:GetActiveWeapon()
    if not IsValid(weapon) then return emptyPayload("nohand") end
    local class = tostring(weapon:GetClass())
    local profile = GquestMech.Profile(class)
    if not profile then return emptyPayload("unsupported", class) end
    local state, code = stateFor(weapon, profile)
    if not state then return emptyPayload("engine", class, code) end
    return statePayload(weapon, profile, state)
end

--- Read-only reply for the panel's poll: sends the state, writes no log line. A poll every
--- half second must not fill the log the evaluator reads.
concommand.Add("gquest_mech_poll", function(player)
    pushState(player, pollPayload(player))
end)

--- The panel follows the hand, not the poll clock: as soon as another weapon is active the new
--- state is pushed, so picking a gun in the menu shows up in the same tick instead of up to half
--- a second later. Only a class change sends anything, and a switch writes no log line.
local lastSeen = setmetatable({}, {__mode = "k"})
function watchHand(player)
    if not IsValid(player) then return end
    local weapon = player.GetActiveWeapon and player:GetActiveWeapon()
    local class = IsValid(weapon) and tostring(weapon:GetClass()) or "none"
    if lastSeen[player] == class then return end
    lastSeen[player] = class
    pushState(player, pollPayload(player))
end

concommand.Add("gquest_mech_state", function(player)
    local weapon = IsValid(player) and player.GetActiveWeapon and player:GetActiveWeapon() or nil
    local class = IsValid(weapon) and tostring(weapon:GetClass()) or "none"
    local profile = IsValid(weapon) and GquestMech.Profile(class) or nil
    if not profile then
        print("GQUEST_MECH state: no supported weapon class=" .. class)
        pushState(player, pollPayload(player))
        return
    end
    local state = stateFor(weapon, profile)
    if not state then
        print("GQUEST_MECH state: unreadable engine state class=" .. class)
        pushState(player, pollPayload(player))
        return
    end
    print(string.format("GQUEST_MECH STATE class=%s kind=%s action=%s capacity=%d chamber=%d mag=%d safety=%s slide=%s inserted=%s stored=%d engine=%s",
        weapon:GetClass(), profile.kind, profile.action, state.binding.capacity, state.chamber,
        state.magazine, tostring(state.safety), tostring(state.slideLocked),
        tostring(state.magazineInserted), state.stored, state.binding.describe()))
    pushState(player, statePayload(weapon, profile, state))
end)

concommand.Add("gquest_mech_rack", function(player)
    local weapon, profile, owner_, ammoType = commandWeapon(player)
    if not weapon then return end
    GquestMech.Rack(weapon, profile, owner_, ammoType)
end)

concommand.Add("gquest_mech_mag", function(player)
    local weapon, profile, owner_, ammoType = commandWeapon(player)
    if not weapon then return end
    local state = stateFor(weapon, profile)
    if not state then return end
    if state.magazineInserted then
        GquestMech.MagazineOut(weapon, profile)
    else
        GquestMech.MagazineIn(weapon, profile, owner_, ammoType)
    end
end)

concommand.Add("gquest_mech_reload", function(player)
    local weapon, profile, owner_, ammoType = commandWeapon(player)
    if not weapon then return end
    GquestMech.Reload(weapon, profile, owner_, ammoType, true)
end)

concommand.Add("gquest_mech_safety", function(player)
    local weapon, profile = commandWeapon(player)
    if not weapon then return end
    GquestMech.Safety(weapon, profile)
end)

concommand.Add("gquest_mech_reset", function(player)
    local weapon = IsValid(player) and player:GetActiveWeapon() or nil
    if not IsValid(weapon) then return end
    states[weapon] = nil
    print("GQUEST_MECH reset class=" .. weapon:GetClass())
end)

CreateConVar(ENABLED_CVAR, "1", FCVAR_ARCHIVE,
    "H3VR-style manual weapon mechanics: chamber, magazine, safety, slide lock")
CreateConVar(WRITE_CHAMBER_CVAR, "0", FCVAR_ARCHIVE,
    "Also write the chambered-round field of native HLVR magazines (off: the native path owns it)")

print("GQUEST_MECH ready: gquest_mech_state / _rack / _mag / _reload / _safety")
