--[[
    Menu_Layout: Masque skins for action icons, when Masque is loaded. The wheel's actions and its
    quick action have their own groups, so each can take a different skin.
]]

local env = select(2, ...)
local Menu_Layout = env.AX_Modules:Import("@\\Menu\\Layout")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")

local Masque = LibStub and LibStub("Masque", true)

--- The Masque groups, by their static ids. Masque saves skins by id, so the names can change
--- with the language. An id must differ from its name, or Masque drops the group's saved
--- settings on each load.
Menu_Layout.MasqueGroup = Utils_Standard.Strict({
    Actions     = "MenuActions", -- the wheel's actions
    QuickAction = "QuickAction", -- the quick action in its center
}, "Masque group")

--- The groups' names in Masque's options.
local GROUP_NAMES = {
    [Menu_Layout.MasqueGroup.Actions] = "Config - Display - Masque - Actions",
    [Menu_Layout.MasqueGroup.QuickAction] = "Config - Display - Masque - QuickAction",
}

---@type table<string, table>
local groups = {}

--- The Masque group `id`, made on first use.
---@param id string a Menu_Layout.MasqueGroup
---@return table
local function GetGroup(id)
    local group = groups[id]
    if not group then
        group = Masque:Group(env.NAME_ALT, env.L[GROUP_NAMES[id]], id)
        groups[id] = group
    end
    return group
end

--- Adds an action icon to the Masque group `groupId`. The skin brings its own mask, so ours
--- comes off the icon. Does nothing without Masque. Skin changes show after a reload.
---
--- The icon shares its parent's frame level and sorts with the wheel's art by draw layer.
--- Skins move its textures to lower layers, under the wheel's background and highlight, so a
--- skinned icon gets its own frame level above the parent instead.
---@param icon ActionIcon
---@param groupId string a Menu_Layout.MasqueGroup
function Menu_Layout.SkinActionIcon(icon, groupId)
    if not Masque then return end
    icon:SetUsingParentLevel(false)
    icon:SetFrameLevel(icon:GetParent():GetFrameLevel() + 1)
    icon.Icon:RemoveMaskTexture(icon.IconMask)
    GetGroup(groupId):AddButton(icon, {
        Icon = icon.Icon,
        Normal = icon.Border,
        Checked = icon.Checked,
        Cooldown = icon.Cooldown,
        ChargeCooldown = icon.ChargeCooldown,
        Count = icon.Count,
    }, "Action")
    icon.skinned = true
    -- Some skins hide the border. Kept so showing an action doesn't bring it back.
    icon.skinShowsBorder = icon.Border:IsShown()
end

-- The groups show in Masque's options from the start, not once a menu first opens (wedges are
-- made on first use).
if Masque then
    for id in pairs(GROUP_NAMES) do GetGroup(id) end
end
