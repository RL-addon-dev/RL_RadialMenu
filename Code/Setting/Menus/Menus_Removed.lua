--[[
    Menus_Removed: the Removed Actions box of a library menu's page in the Menus tab (see
    Tab.lua), under Menu Settings. It's shown only while the user has removed actions from it (the
    X in the preview, Menu_Data Library.lua): one row per action, with its icon and name as they
    were when removed, and Restore, then Restore All when there are several. A restored action
    comes back at once if the menu has it right now (a quest item you still have), else whenever
    it does.
]]

local env = select(2, ...)
local L = env.L
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local _, _, _, LayoutVertical = unpack(UIKit.UI.Frames)
local Setting_Widgets = env.AX_Modules:Import("@\\Setting\\Widgets")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Utils_Text = env.AX_Modules:Import("@\\Utils\\Text")
local Menus_Removed = env.AX_Modules:New("@\\Setting\\Menus\\Removed")

local format = string.format

local ICON_SIZE = 16
local ROW_SPACING = 10
local ATLAS_PREFIX = "atlas:" -- icons may be atlases (Menu_Layout.SetIcon)

--- "<icon> Name" for a row title, with the icon as a text escape (a file or id, or an atlas).
---@param icon number|string|nil
---@param label string?
---@return string
local function IconAndName(icon, label)
    local name = Utils_Text.Escape(label)
    if type(icon) == "string" and icon:sub(1, #ATLAS_PREFIX) == ATLAS_PREFIX then
        return format("|A:%s:%d:%d|a %s", icon:sub(#ATLAS_PREFIX + 1), ICON_SIZE, ICON_SIZE, name)
    elseif icon then
        return format("|T%s:%d|t %s", tostring(icon), ICON_SIZE, name)
    end
    return name
end

local BoxMixin = {}

--- Row `index`, made on first use.
---@param index integer
---@return table
function BoxMixin:GetRow(index)
    local row = self.rows[index]
    if row then return row end
    row = Setting_Widgets.ElementButton(self.rowPrefix .. index)
    row:parent(self.List)
    row:GetButton():SetText(L["Config - Menus - Removed - Restore"])
    row:GetButton():HookClick(function()
        if self.menuId and row.key then Menu_Data.RestoreRemoved(self.menuId, row.key) end
    end)
    row:_Render()
    self.rows[index] = row
    return row
end

--- Fills the box for library menu `menu`, or hides it while nothing's removed (or `menu` isn't a library menu).
---@param menu Menu?
function BoxMixin:SetMenu(menu)
    local removed = Menu_Data.IsLibraryMenu(menu) and Menu_Data.GetRemovedActions(menu) or {}
    self.menuId = menu and menu.id
    self:SetShown(#removed > 0)
    self.Title:SetText(format(L["Config - Menus - Removed - Title"], #removed))
    for index, entry in ipairs(removed) do
        local row = self:GetRow(index)
        row.key = entry.key
        row:SetInfo(IconAndName(entry.icon, entry.label), nil)
        row:Show()
    end
    for index = #removed + 1, #self.rows do
        self.rows[index]:Hide()
        self.rows[index].key = nil
    end
    self.RestoreAllRow:SetShown(#removed > 1)
end

--- Sets up the box's texts and Restore All.
function BoxMixin:Setup()
    self.rows = {}
    self:SetSubcontainer(false)
    self.RestoreAllRow:SetInfo(L["Config - Menus - Removed - All"], nil)
    self.RestoreAllRow:GetButton():SetText(L["Config - Menus - Removed - RestoreAll"])
    self.RestoreAllRow:GetButton():HookClick(function()
        if self.menuId then Menu_Data.RestoreRemoved(self.menuId) end
    end)
    self:Hide()
end

Menus_Removed.Box = UIKit.Template(function(id, name, children, ...)
    local frame =
        Setting_Widgets.ContainerWithTitle(name, {
            -- One row per removed action (GetRow).
            LayoutVertical(name .. ".List")
                :id("List", id)
                :size(UIKit.UI.P_FILL, UIKit.Define.Fit{})
                :layoutSpacing(ROW_SPACING)
                :_updateMode(UIKit.Enum.UpdateMode.ChildrenVisibilityChanged),
            Setting_Widgets.ElementButton(name .. ".RestoreAll"):id("RestoreAllRow", id)
        })

    frame.List = UIKit.GetElementById("List", id)
    frame.RestoreAllRow = UIKit.GetElementById("RestoreAllRow", id)
    frame.rowPrefix = name .. ".Row"

    Mixin(frame, BoxMixin)

    return frame
end)
