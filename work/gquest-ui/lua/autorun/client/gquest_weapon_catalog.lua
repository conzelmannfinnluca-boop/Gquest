-- One tracked Derma surface; selecting a weapon closes it before firing resumes.
local frame

-- The mechanics state lives on the server, so the panel asks for it and draws the reply. The
-- poll prints nothing on the server: the log belongs to the hardware evaluator, not to a label.
GQUEST_MECH_LIVE = GQUEST_MECH_LIVE or "none"
local liveLabel
-- Set while a pick is on its way to the server: the line then describes that pick, and the
-- panel closes as soon as that weapon is really in hand.
local pendingClass

local function closePanel()
    if IsValid(frame) then frame:Close() end
    gui.HideGameUI()
end

-- Names from this catalog, so a weapon without mechanics is named the way the menu names it.
local NAMES = {
    weapon_pistol = "Pistole", weapon_357 = ".357 Revolver", weapon_smg1 = "SMG",
    weapon_ar2 = "AR2", weapon_shotgun = "Schrotflinte", weapon_crossbow = "Armbrust",
    weapon_rpg = "Raketenwerfer", weapon_crowbar = "Brechstange", weapon_frag = "Granate",
    weapon_physcannon = "Gravity Gun", weapon_physgun = "Physgun",
}
local SUPPORTED = "Pistole, .357, SMG, AR2, Schrotflinte, Armbrust, RPG"
-- The server flattens its engine reason to a code; these are the ones it can send.
local CODES = {
    weapon_has_no_clip = "kein Magazin am Modell",
    weapon_has_no_magazine = "kein lesbares Magazin",
    native_capacity_invalid = "Magazingroesse unlesbar",
    clip_unreadable = "Magazinstand unlesbar",
}

local function weaponName(class)
    if type(class) ~= "string" then return "unbekannt" end
    -- Native HLVR classes are the same guns with a prefix; the catalog names are unprefixed.
    local key = class
    if string.sub(class, 1, 5) == "hlvr_" then key = "weapon_" .. string.sub(class, 6) end
    return NAMES[key] or class
end

local function liveText(payload)
    if type(payload) ~= "string" or payload == "" or payload == "none" then
        return "Waffe: keine mit Mechanik in der Hand"
    end
    local field = {}
    for key, value in string.gmatch(payload, "(%a+)=([^ ]+)") do field[key] = value end
    if not field.chamber then
        -- No numbers: name the weapon and the reason instead of leaving the line empty.
        if field.state == "pending" then
            return string.format("Waffe: %s wird ausgeruestet ...", weaponName(field.class))
        end
        if field.reason == "nohand" then
            return "Waffe: nichts in der Hand - Mechanik nur fuer " .. SUPPORTED
        end
        if field.reason == "dead" then return "Waffe: Spieler tot - keine Mechanik" end
        if field.reason == "unsupported" then
            return string.format("Waffe: %s (%s) - hat keine Mechanik, nur %s",
                weaponName(field.class), field.class or "?", SUPPORTED)
        end
        if field.reason == "engine" then
            local code = field.code or "unbekannt"
            return string.format("Waffe: %s (%s) - %s", weaponName(field.class),
                field.class or "?", CODES[code] or string.gsub(code, "_", " "))
        end
        return "Waffe: keine Mechanik-Daten"
    end
    local safety = field.safety == "true" and "Sicherung an" or "Sicherung aus"
    local slide = field.slide == "true" and "Verschluss offen" or "Verschluss zu"
    local magazine = field.inserted == "false" and ", Magazin draussen" or ""
    -- One line, always starting with "Waffe:", so the label stays recognisable and the panel
    -- can find it again after an update.
    return string.format("Waffe: %s - Kammer %s, Magazin %s/%s, %s, %s%s",
        field.class or "unbekannt", field.chamber, field.mag, field.capacity or "?",
        safety, slide, magazine)
end

local function renderLive()
    if IsValid(liveLabel) then liveLabel:SetText(liveText(GQUEST_MECH_LIVE)) end
end

--- How long the confirmed line stays readable: the value the player set in the VR settings,
--- read per pick so a change applies to the next weapon. A missing profile module falls back
--- to the default instead of closing instantly.
local function confirmReadTime()
    local profiles = GQUEST_PROFILES
    if profiles and profiles.ReadTimeSeconds then
        local seconds = profiles.ReadTimeSeconds()
        if type(seconds) == "number" and seconds >= 0 and seconds <= 5 then return seconds end
    end
    return 0.3
end

--- Does this payload describe the class the player just picked? Native HLVR guns carry a
--- prefix on the same weapon_catalog name.
local function namesClass(payload, class)
    if type(payload) ~= "string" then return false end
    local found = string.match(payload, "class=([^ ]+)")
    if not found then return false end
    if found == class then return true end
    return "weapon_" .. string.gsub(found, "^hlvr_", "") == class
end

if net and net.Receive then
    net.Receive("GquestMechState", function()
        local payload = net.ReadString() or "none"
        -- While a pick is pending, ignore answers about the old gun: the line must not fall back
        -- to the weapon the player just replaced.
        if pendingClass and not namesClass(payload, pendingClass) then return end
        GQUEST_MECH_LIVE = payload
        renderLive()
        if pendingClass then
            -- Confirmed: let the line be read for a moment, then back to the game.
            pendingClass = nil
            timer.Remove("GquestMechPending")
            timer.Create("GquestMechClose", confirmReadTime(), 1, closePanel)
        end
    end)
end
local groups={
    {"Half-Life 2", "gquest_hl2_equip",{
        {"Pistole", "weapon_pistol"},{".357 Revolver", "weapon_357"},
        {"SMG", "weapon_smg1"},{"AR2", "weapon_ar2"},
        {"Schrotflinte", "weapon_shotgun"},{"Armbrust", "weapon_crossbow"},
        {"Raketenwerfer", "weapon_rpg"},{"Brechstange", "weapon_crowbar"},
        {"Granate", "weapon_frag"},{"Gravity Gun", "weapon_physcannon"},
        {"Physgun", "weapon_physgun"}}}

}
GquestWeapons=GquestWeapons or {}
function GquestWeapons.IsMenuVisible() return IsValid(frame) and frame:IsVisible() end
function GquestWeapons.Open()
    if IsValid(frame) then frame:Close() end
    gui.HideGameUI()
    -- A reopened panel starts from the server's answer, not from an abandoned pick.
    pendingClass=nil
    timer.Remove("GquestMechPending")
    timer.Remove("GquestMechClose")
    frame=vgui.Create("DFrame")
    frame:SetTitle("Gquest Waffen")
    frame:SetSize(math.min(660,ScrW()-48),math.min(650,ScrH()-48))
    frame:Center();frame:SetDeleteOnClose(true);frame:MakePopup()
    frame:SetKeyboardInputEnabled(false)
    local close=vgui.Create("DButton",frame);close:Dock(BOTTOM);close:SetTall(48)
    close:SetText("Zurueck zum Spiel");close.DoClick=closePanel
    local reload=vgui.Create("DButton",frame);reload:Dock(TOP);reload:SetTall(48)
    reload:SetText("Nachladen / HL2-Magazin auswerfen")
    reload.DoClick=function() frame:Close();gui.HideGameUI();RunConsoleCommand("gquest_reload") end
    -- Live chamber and magazine, from the server's own numbers.
    local live=vgui.Create("DLabel",frame);live:Dock(TOP)
    live:SetFont("DermaDefaultBold")
    -- A reason can be longer than the panel is wide, so the line wraps and grows instead of
    -- being cut off mid sentence.
    live:SetWrap(true);live:SetAutoStretchVertical(true);live:SetTall(30)
    liveLabel=live;renderLive()
    RunConsoleCommand("gquest_mech_poll")
    timer.Create("GquestMechPoll",0.5,0,function()
        if not IsValid(frame) or not frame:IsVisible() then timer.Remove("GquestMechPoll") return end
        RunConsoleCommand("gquest_mech_poll")
    end)
    -- Weapon actions a headset cannot type: the mechanics commands, one click each. The rules
    -- live in the server module; these buttons only issue its commands, and the panel stays
    -- open so several actions in a row cost one gesture each instead of a reopened menu.
    local actions={
        {"Magazin","gquest_mech_mag"},{"Durchladen","gquest_mech_rack"},
        {"Nachladen","gquest_mech_reload"},{"Sicherung","gquest_mech_safety"},
        {"Zustand","gquest_mech_state"},{"Haende","gquest_hands_state"},
    }
    -- Same width the frame was sized to above, so the three columns line up before the
    -- panel has been laid out.
    local actionWidth=math.floor(math.min(660,ScrW()-48)/3)
    for row=1,2 do
        local strip=vgui.Create("DPanel",frame);strip:Dock(TOP);strip:SetTall(52)
        for column=1,3 do
            local entry=actions[(row-1)*3+column]
            local control=vgui.Create("DButton",strip)
            control:Dock(LEFT);control:DockMargin(2,2,2,2)
            control:SetWide(actionWidth-6);control:SetText(entry[1])
            control.DoClick=function()
                RunConsoleCommand(entry[2])
                print("GQUEST_WEAPON_MENU command="..entry[2])
            end
        end
    end
    local columns=vgui.Create("DPanel",frame);columns:Dock(FILL)
    for _,group in ipairs(groups) do
        local list=vgui.Create("DScrollPanel",columns);list:Dock(FILL)
        list:DockMargin(2,2,2,2)
        local heading=vgui.Create("DLabel",list);heading:Dock(TOP);heading:SetTall(32)
        heading:SetText(group[1]);heading:SetFont("DermaDefaultBold")
        for _,entry in ipairs(group[3]) do
            local command,class=group[2],entry[2]
            local button=vgui.Create("DButton",list);button:Dock(TOP)
            button:DockMargin(2,3,2,3);button:SetTall(48);button:SetText(entry[1])
            button.DoClick=function()
                -- Answer the click before the server does: the line names what is being
                -- equipped instead of showing the previous weapon while the reply is in
                -- flight. The panel closes once that weapon is confirmed, or after a second.
                pendingClass=class
                GQUEST_MECH_LIVE="state=pending class="..class
                renderLive()
                timer.Create("GquestMechPending",0.6,1,function()
                    pendingClass=nil
                    closePanel()
                    RunConsoleCommand("gquest_mech_poll")
                end)
                RunConsoleCommand(command,class)
                print("GQUEST_WEAPON_MENU selected="..class)
            end
        end
    end
    print("GQUEST_WEAPON_MENU opened")
end
concommand.Add("gquest_weapons",GquestWeapons.Open)
