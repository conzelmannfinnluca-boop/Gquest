-- Gquest's own client UI; native GDroid provides the tracked Derma surface.
local rootFrame,alignFrame
local openRoot
-- Space the frame spends outside the scrolled content: the button row plus the title bar.
-- The title height is an estimate from DFrame's default skin, not a measurement.
local SETTINGS_BUTTON_ROW,SETTINGS_TITLE_ALLOWANCE=54,32
local SETTINGS_CHROME=SETTINGS_BUTTON_ROW+SETTINGS_TITLE_ALLOWANCE
GquestUI=GquestUI or {}
GquestUI.SETTINGS_CHROME=SETTINGS_CHROME
GquestUI=GquestUI or {}
function GquestUI.IsMenuVisible()
    return (IsValid(rootFrame) and rootFrame:IsVisible()) or (IsValid(alignFrame) and alignFrame:IsVisible()) or false
end
local menuBlockedUntil=0
-- Profiles live in gquest_vr_profiles.lua so the menu and the boundary test share
-- one implementation. See that file for the file format and the device tier sets.
local profiles = GQUEST_PROFILES
local profileState = profiles and profiles.Load() or nil
local function saveProfile()
    if profiles and profileState then profiles.Save(profileState) end
end
local function applyProfile()
    if not profileState then return end
    RunConsoleCommand("vr_eye_resolution", profileState.tier)
    RunConsoleCommand("vr_ffr_level", tostring(profileState.foveation))
    RunConsoleCommand("vr_refresh_rate", tostring(profileState.rate))
end
-- The turn itself lives in gquest_playspace.lua; the menu owns only the step width, so
-- there is one implementation of the turn. Called once at load and again on every change,
-- which is why a saved step already applies before the menu is ever opened.
local function applyComfort()
    if GquestPlayspace and profileState and profileState.snapStep then
        GquestPlayspace.STEP = profileState.snapStep
    end
    -- The profile stores the name, gquest_hand_smoothing.lua owns what it means; an unknown
    -- name is refused there and the current setting stays.
    if GquestHandSmoothing and GquestHandSmoothing.SetLevel and profileState and
        profileState.smoothing then
        GquestHandSmoothing.SetLevel(profileState.smoothing)
    end
end
applyComfort()
local function closeRoot()
    menuBlockedUntil=RealTime()+1.25
    if IsValid(rootFrame) then rootFrame:Close() end
    rootFrame = nil
end
local function spawnToggle()
    closeRoot()
    gui.HideGameUI()
    if not IsValid(g_SpawnMenu) then
        notification.AddLegacy("Spawn-Menue ist in diesem Spielmodus nicht verfuegbar.", NOTIFY_ERROR, 4)
        return
    end
    if g_SpawnMenu:IsVisible() then hook.Run("OnSpawnMenuClose")
    else
        hook.Run("OnSpawnMenuOpen")
        timer.Simple(0.15,function()
            if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then
                g_SpawnMenu:MakePopup()
                print("GQUEST_UI spawn focus acquired")
            end
        end)
    end
end
-- Runs the weapon-model report (gquest_weapon_models.lua) and shows its
-- summary in-headset. The report itself only reads and prints.
local function weaponModelCheck()
    local module = GQUEST_WEAPON_MODELS
    if not module or not module.Run then
        RunConsoleCommand("gquest_wmodel")
        notification.AddLegacy("Waffenmodelle werden geprueft, Ergebnis im Log.", NOTIFY_GENERIC, 4)
        return
    end
    local ok, matched, missingRight, missingLeft, partsMissing = pcall(module.Run, false)
    if not ok then
        notification.AddLegacy("Waffenmodell-Pruefung fehlgeschlagen: " .. tostring(matched), NOTIFY_ERROR, 6)
        return
    end
    local text = string.format("Waffenmodelle %d/12 ok, fehlend rechts %d / links %d, Teile fehlen %d",
        matched, missingRight, missingLeft, partsMissing)
    notification.AddLegacy(text, (missingRight + missingLeft + partsMissing) > 0 and NOTIFY_ERROR or NOTIFY_GENERIC, 8)
end
-- The alignment controls live in gquest_weapon_align.lua; this only hosts them
-- in a frame so the menu keeps one code path for opening and closing panels.
local function openAlign()
    local builder = GQUEST_WEAPON_ALIGN and GQUEST_WEAPON_ALIGN.BuildPanel
    if not builder then
        RunConsoleCommand("gquest_align")
        notification.AddLegacy("Ausrichtung nur per Konsole: gquest_align_status", NOTIFY_GENERIC, 5)
        return
    end
    closeRoot(); gui.HideGameUI()
    if IsValid(alignFrame) then alignFrame:Close() end
    alignFrame = vgui.Create("DFrame")
    alignFrame:SetTitle("Waffen ausrichten")
    alignFrame:SetSize(math.min(660, ScrW() - 48), math.min(660, ScrH() - 48))
    alignFrame:Center(); alignFrame:SetDeleteOnClose(true); alignFrame:MakePopup()
    alignFrame:SetKeyboardInputEnabled(false)
    alignFrame:SetMouseInputEnabled(true)
    local frame = alignFrame
    timer.Simple(0.15, function()
        if not IsValid(frame) then return end
        frame:MakePopup(); frame:SetKeyboardInputEnabled(false)
        frame:SetMouseInputEnabled(true); frame:MoveToFront()
        print("GQUEST_UI align focus acquired")
    end)
    local back = vgui.Create("DButton", frame); back:Dock(TOP); back:SetTall(46)
    back:SetText("Zurueck")
    back.DoClick = function() frame:Close(); openRoot(true) end
    local panel = builder(frame)
    panel:Dock(FILL)
    print("GQUEST_UI align opened")
end
local function settingsPanel(parent)
    local panel = vgui.Create("DScrollPanel", parent)
    -- Two columns. As one stack the pane grew to 1296 px against 970 px of usable screen,
    -- which left 326 px behind a scrollbar nobody drags in a headset. Bildprofil and comfort
    -- keys share the left column, the weapon tools the right one; each column keeps its own
    -- cursor and the pane reports the taller of the two.
    local columnWidth = 280
    local columnX = { 16, math.min(680, ScrW() - 48) - 24 - columnWidth }
    local column = 1
    local y = { 12, 12 }
    -- Wrapped text needs a budget that follows the column width, otherwise a paragraph reserves
    -- one line for text that now takes three and the rest is clipped.
    local function charBudget()
        local base = (profiles and profiles.STATUS_LINE_BUDGET) or 60
        return math.max(18, math.floor(base * columnWidth / 580))
    end
    local function text(value, height, tint)
        local label = panel:Add("DLabel")
        label:SetText(value); label:SetFont("DermaDefaultBold"); label:SetWrap(true)
        label:SetTextColor(tint or Color(235,235,235))
        label:SetPos(columnX[column], y[column]); label:SetSize(columnWidth, height)
        y[column] = y[column] + height + 12
    end
    -- Like text(), but the reserved height follows the string length, so a long device
    -- name wraps into a second row instead of being cut off at the label edge.
    local function statusLine(value, tint)
        local lines = math.max(1, math.ceil(#value / charBudget()))
        local label = panel:Add("DLabel")
        label:SetText(value); label:SetFont("DermaDefaultBold"); label:SetWrap(true)
        label:SetAutoStretchVertical(true)
        label:SetTextColor(tint or Color(235,235,235)); label:SetPos(columnX[column], y[column])
        label:SetSize(columnWidth, 24 * lines)
        y[column] = y[column] + 24 * lines + 12
    end
    -- Help paragraphs wrap, so their reserved height follows their length instead of a guess.
    -- A fixed height shorter than the wrapped text clips it.
    local function para(value)
        text(value, 24 * math.max(1, math.ceil(#value / charBudget())))
    end
    local function combo(title, choices, selected, changed)
        -- The title wraps at the column width too, so a long one gets two rows.
        para(title)
        local box = panel:Add("DComboBox")
        box:SetPos(columnX[column], y[column]); box:SetSize(columnWidth,42)
        box:SetSortItems(false)
        for _, entry in ipairs(choices) do box:AddChoice(entry[1],entry[2],entry[2]==selected) end
        box.OnSelect = function(_,_,_,data) changed(data) end
        y[column] = y[column] + 58
    end
    local function button(size)
        local b = panel:Add("DButton")
        b:SetPos(columnX[column], y[column]); b:SetSize(columnWidth, size or 46)
        y[column] = y[column] + (size or 46) + 12
        return b
    end
    para("VR-Einstellungen")
    if not (profiles and profileState) then
        para("Profilmodul gquest_vr_profiles.lua fehlt; nur die Bildprofile sind gesperrt. " ..
             "Die uebrigen Funktionen bleiben nutzbar.")
    else
        local device = profiles.DEVICES[profileState.device]
        local deviceChoices = {}
        for _, id in ipairs(profiles.ORDER) do
            deviceChoices[#deviceChoices+1] = { profiles.DEVICES[id].label, id }
        end
        combo("Geraet", deviceChoices, profileState.device, function(value)
            if value == profileState.device then return end
            profiles.SetDevice(profileState, value)
            saveProfile(); applyProfile()
            print("GQUEST_PROFILE device="..value.." tier="..profileState.tier)
            notification.AddLegacy(profiles.DEVICES[value].label..": "..profileState.tier
                ..", FFR "..profileState.foveation..", "..profileState.rate.." Hz", NOTIFY_GENERIC, 5)
            -- The tier list belongs to the device, so the panel is rebuilt once the
            -- current combo callback has returned.
            timer.Simple(0, function() openRoot(true) end)
        end)
        -- Show what the bridge detected, so a device mismatch is visible here
        -- instead of only showing up as unexpected performance in the headset.
        local detected = profiles.Detected()
        local statusText, severity = profiles.DetectionLabel(profileState, detected)
        local severityColors = {
            match = Color(120,200,140), mismatch = Color(230,160,90), none = Color(170,170,170)
        }
        statusLine(statusText, severityColors[severity])
        if severity == "mismatch" and detected then
            local detectedDevice = profiles.DEVICES[detected]
            local adopt = button()
            adopt:SetText("Auf "..detectedDevice.label.." umstellen (Empfehlung)")
            adopt.DoClick = function()
                if not profiles.AdoptDetected(profileState, detected) then return end
                saveProfile(); applyProfile()
                print("GQUEST_PROFILE adopted="..profileState.device.." tier="..profileState.tier)
                notification.AddLegacy(detectedDevice.label.." uebernommen: "..profileState.tier
                    ..", FFR "..profileState.foveation..", "..profileState.rate
                    .." Hz. Bildprofil gilt nach Neustart.", NOTIFY_GENERIC, 5)
                timer.Simple(0, function() openRoot(true) end)
            end
        end
        local tierChoices = {}
        for index, tier in ipairs(device.tiers) do
            tierChoices[#tierChoices+1] = { string.format("%s - %s", device.tier_labels[index], tier), index }
        end
        combo("Bildprofil "..device.label.." (nach Neustart)", tierChoices, profileState.tierIndex, function(index)
            profiles.SetTier(profileState, index); saveProfile(); applyProfile()
        end)
        combo("Randaufloesung: mehr Reduktion spart Grafikleistung", {
            {"Keine Reduktion",0},{"Wenig",1},{"Mittel",2},{"Stark",3}
        },profileState.foveation,function(value)
            profiles.SetFoveation(profileState,value); saveProfile(); applyProfile()
        end)
        combo("Bildwiederholrate", {{"72 Hz",72},{"90 Hz",90}},profileState.rate,function(value)
            profiles.SetRate(profileState,value); saveProfile(); applyProfile()
        end)
    end
    if profiles and profileState then
        para("Playspace")
        para("Snap-Turn dreht den Blick in Schritten (Konsole: gquest_snap_ccw / gquest_snap_cw), sofort wirksam. Sitzend wird gespeichert, wirkt aber erst mit dem Core-Umstieg.")
        -- Buttons instead of dropdowns: with a controller in a headset a cycling button
        -- is one click, a combo box is a focus change and a list.
        local stepButton=button()
        local function stepText()
            return string.format("Snap-Turn: %d Grad (klicken zum Wechseln)",profileState.snapStep)
        end
        stepButton:SetText(stepText())
        stepButton.DoClick=function()
            profiles.CycleSnapStep(profileState); saveProfile(); applyComfort()
            stepButton:SetText(stepText())
            notification.AddLegacy("Snap-Turn "..profileState.snapStep.." Grad",NOTIFY_GENERIC,3)
        end
        local stanceButton=button()
        local function stanceText()
            return "Fortbewegung: "..(profileState.stance=="seated" and "Sitzend" or "Stehend")
        end
        stanceButton:SetText(stanceText())
        stanceButton.DoClick=function()
            profiles.ToggleStance(profileState); saveProfile()
            stanceButton:SetText(stanceText())
            notification.AddLegacy(profileState.stance=="seated"
                and "Sitzend gespeichert (wirkt mit dem Core-Umstieg)" or "Stehend gespeichert",NOTIFY_GENERIC,4)
        end
        local SMOOTHING_LABELS={ off="Aus", mild="Mild", strong="Stark" }
        local function smoothingText()
            return "Handglaettung: "..(SMOOTHING_LABELS[profileState.smoothing] or profileState.smoothing)
                .." (klicken zum Wechseln)"
        end
        local smoothingButton=button()
        smoothingButton:SetText(smoothingText())
        smoothingButton.DoClick=function()
            profiles.CycleSmoothing(profileState); saveProfile(); applyComfort()
            smoothingButton:SetText(smoothingText())
            notification.AddLegacy("Handglaettung: "
                ..(SMOOTHING_LABELS[profileState.smoothing] or profileState.smoothing),NOTIFY_GENERIC,3)
        end
    end
    -- Right column: the weapon tools, independent of the profile keys on the left.
    column = 2
    para("Waffenmodelle")
    para("Prueft im laufenden Spiel, welches Handmodell jede Waffe tatsaechlich benutzt und ob alle Modelle geladen werden. Das Ergebnis steht im Log und in data/gquest/weapon_models.json.")
    local modelCheck=button(); modelCheck:SetText("Waffenmodelle pruefen")
    modelCheck.DoClick=weaponModelCheck
    para("Ausrichtung")
    para("Waffenhaltung pro Modell pruefen und feinjustieren. Die native Quest-Darstellung wird nicht von jeder VRMod-Einstellung beeinflusst.")
    local alignButton=button(); alignButton:SetText("Waffe ausrichten")
    alignButton.DoClick=openAlign
    para("Leistung liefert ein weicheres Bild. Ausgewogen und Schaerfer kosten mehr GPU-Zeit. Jedes Geraet hat eigene Stufen und merkt sich seine letzte Wahl. Das Bildprofil wird beim naechsten Start angewendet.")
    if profiles and profileState then
        local resetLabel = profiles.DEVICES[profileState.device].label
        local reset=button(); reset:SetText("Empfohlen fuer "..resetLabel.." wiederherstellen")
        reset.DoClick=function()
            profiles.Recommend(profileState); saveProfile(); applyProfile()
            notification.AddLegacy("Empfohlen fuer "..resetLabel.." gespeichert. Bildprofil gilt nach Neustart.",NOTIFY_GENERIC,4)
        end
    end
    -- The frame sizes itself from this instead of a fixed 680, so a section that does not
    -- fit grows the panel rather than hiding behind a scrollbar nobody scrolls in a headset.
    panel.ContentHeight = math.max(y[1], y[2])
    return panel
end
openRoot=function(settings)
    closeRoot(); gui.HideGameUI()
    rootFrame=vgui.Create("DFrame")
    local frameWidth=math.min(680,ScrW()-48)
    rootFrame:SetTitle("Gquest VR"); rootFrame:SetSize(frameWidth,math.min(680,ScrH()-48))
    rootFrame:Center(); rootFrame:SetDeleteOnClose(true); rootFrame:MakePopup()
    rootFrame:SetKeyboardInputEnabled(false)
    rootFrame:SetMouseInputEnabled(true); rootFrame:MoveToFront()
    local frame=rootFrame
    timer.Simple(0.15,function()
        if not IsValid(frame) or frame~=rootFrame then return end
        frame:MakePopup(); frame:SetKeyboardInputEnabled(false)
        frame:SetMouseInputEnabled(true); frame:MoveToFront()
        print("GQUEST_UI focus acquired")
    end)
    local buttons=vgui.Create("DPanel",rootFrame); buttons:Dock(TOP); buttons:SetTall(SETTINGS_BUTTON_ROW)
    -- Four buttons share the row; the previous fixed 196 px would overflow the
    -- frame width once a fourth control was added.
    local buttonWidth=math.max(140, math.floor(rootFrame:GetWide()/4)-8)
    local function button(title,action)
        local b=vgui.Create("DButton",buttons); b:Dock(LEFT); b:DockMargin(4,4,4,4); b:SetWide(buttonWidth); b:SetText(title); b.DoClick=function() print("GQUEST_UI click="..title); action() end
    end
    button("Spawn-Menue",spawnToggle)
    button("VR-Einstellungen",function() openRoot(true) end)
    button("Waffen",function() closeRoot();RunConsoleCommand("gquest_weapons") end)
    button("Zurueck zum Spiel",function() closeRoot(); gui.HideGameUI() end)
    local panel=settingsPanel(rootFrame); panel:Dock(FILL)
    -- Total height asked for: content plus the chrome that is not scrolled. Clamped to the
    -- screen and to a minimum, so a short panel does not become a stamp.
    rootFrame:SetSize(frameWidth,math.min(ScrH()-48,math.max(420,(panel.ContentHeight or 0)+SETTINGS_CHROME)))
    -- Kept for the boundary test: without it the only evidence of the size decision would be
    -- the print below, which a test cannot read.
    rootFrame.ContentHeight=panel.ContentHeight
    rootFrame:Center()
    print("GQUEST_UI opened settings="..tostring(settings==true).." content="..tostring(panel.ContentHeight))
end
concommand.Add("gquest_menu",function() openRoot(false) end)
concommand.Add("gquest_settings",function() openRoot(true) end)
concommand.Add("gquest_spawnmenu",spawnToggle)
hook.Add("AddToolMenuCategories","GquestCategory",function()
    spawnmenu.AddToolCategory("Utilities","Gquest","Gquest")
end)
hook.Add("PopulateToolMenu","GquestSettings",function()
    spawnmenu.AddToolMenuOption("Utilities","Gquest","GquestVRSettings","VR-Einstellungen","","",function(panel)
        panel:ClearControls()
        panel:Button("VR-Einstellungen oeffnen","gquest_settings")
        panel:Button("Gquest-Menue oeffnen","gquest_menu")
        panel:Button("Waffenmodelle pruefen","gquest_wmodel")
        panel:Button("Waffe ausrichten","gquest_align")
        panel:Help("Ausrichtung: gespeicherte Werte in data/gquest/weapon_align.json.")
        panel:Help("Bildprofil, Randaufloesung und Bildwiederholrate, je Geraet getrennt.")
        panel:Help("Waffenmodell-Bericht: gquest_wmodel oder gquest_wmodel_verbose.")
    end)
end)
if spawnmenu and spawnmenu.AddCreationTab then
    spawnmenu.AddCreationTab("Gquest VR",function()
        local panel=vgui.Create("DPanel")
        local button=vgui.Create("DButton",panel); button:Dock(TOP); button:SetTall(64)
        button:SetText("Gquest VR-Einstellungen"); button.DoClick=function() openRoot(true) end
        return panel
    end,"icon16/controller.png",99,"Quest VR-Einstellungen")
end
local gameUIWasVisible=false
hook.Add("Think","GquestPauseMenu",function()
    local visible=gui.IsGameUIVisible()
    local spawnVisible=IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible()
    if visible and not gameUIWasVisible and IsValid(LocalPlayer()) and
        RealTime()>menuBlockedUntil and not spawnVisible then
        if not IsValid(rootFrame) then openRoot(false)
        end
    end
    gameUIWasVisible=gui.IsGameUIVisible()
end)
-- The native PANEL menu and Lua Derma must not compete for controller input.
RunConsoleCommand("vr_panel_menu_auto","0")
RunConsoleCommand("gmod_derma_vr_debug","1")
RunConsoleCommand("cl_drawhud","1")
RunConsoleCommand("vr_hud_in_world","1")
RunConsoleCommand("vr_weapon_hud","1")
print("GQUEST_UI ready: settings and spawn-menu controls registered")

local lastWeapon
hook.Add("Think","GquestWeaponDiagnostic",function()
    local player=LocalPlayer()
    if not IsValid(player) then return end
    local weapon=player:GetActiveWeapon()
    if not IsValid(weapon) or weapon==lastWeapon then return end
    lastWeapon=weapon
    print("GQUEST_WEAPON class="..weapon:GetClass().." model="..tostring(weapon:GetModel()).." world="..tostring(weapon.WorldModel).." view="..tostring(weapon.ViewModel))
end)
