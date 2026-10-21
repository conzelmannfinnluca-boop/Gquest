-- One tracked Derma surface; selecting a weapon closes it before firing resumes.
local frame
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
    frame=vgui.Create("DFrame")
    frame:SetTitle("Gquest Waffen")
    frame:SetSize(math.min(660,ScrW()-48),math.min(650,ScrH()-48))
    frame:Center();frame:SetDeleteOnClose(true);frame:MakePopup()
    frame:SetKeyboardInputEnabled(false)
    local close=vgui.Create("DButton",frame);close:Dock(BOTTOM);close:SetTall(48)
    close:SetText("Zurueck zum Spiel");close.DoClick=function() frame:Close();gui.HideGameUI() end
    local reload=vgui.Create("DButton",frame);reload:Dock(TOP);reload:SetTall(48)
    reload:SetText("Nachladen / HL2-Magazin auswerfen")
    reload.DoClick=function() frame:Close();gui.HideGameUI();RunConsoleCommand("gquest_reload") end
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
                frame:Close();gui.HideGameUI()
                RunConsoleCommand(command,class)
                print("GQUEST_WEAPON_MENU selected="..class)
            end
        end
    end
    print("GQUEST_WEAPON_MENU opened")
end
concommand.Add("gquest_weapons",GquestWeapons.Open)
