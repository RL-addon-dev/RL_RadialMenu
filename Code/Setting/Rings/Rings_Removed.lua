--[[
    Removed Actions box of a built-in menu's page in the Menus tab (see Tab.lua), under Menu
    Settings. Shown only while the user has removed actions from it (the X in the preview,
    Ring_Data BuiltIn.lua): one row per action, its icon and name as they were when removed,
    with Restore; then Restore All when there are several. A restored action comes back at once
    if the menu has it right now (a quest item you still have), else whenever it does.
]]

local env = select(2, ...)
local L = env.L
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local _, _, _, LayoutVertical = unpack(UIKit.UI.Frames)
local Setting_Widgets = env.AX_Modules:Import("@\\Setting\\Widgets")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Rings_Removed = env.AX_Modules:New("@\\Setting\\Rings\\Removed")

local format = string.format

local ICON_SIZE = 16
local ATLAS_PREFIX = "atlas:" -- icons may be atlases (Ring_Layout.SetIcon)

--- "<icon> Name" for a row title: the icon as a text escape (a file / id, or an atlas).
local function IconAndName(icon, label)
    local name = tostring(label or ""):gsub("|", "||")
    if type(icon) == "string" and icon:sub(1, #ATLAS_PREFIX) == ATLAS_PREFIX then
        return format("|A:%s:%d:%d|a %s", icon:sub(#ATLAS_PREFIX + 1), ICON_SIZE, ICON_SIZE, name)
    elseif icon then
        return format("|T%s:%d|t %s", tostring(icon), ICON_SIZE, name)
    end
    return name
end

local BoxMixin = {}

function BoxMixin:GetRow(index)
    local row = self.rows[index]
    if row then return row end
    row = Setting_Widgets.ElementButton(self.rowPrefix .. index)
    row:parent(self.List)
    row:GetButton():SetText(L["Config - Rings - Removed - Restore"])
    row:GetButton():HookClick(function()
        if self.ringId and row.key then Ring_Data.RestoreRemoved(self.ringId, row.key) end
    end)
    row:_Render()
    self.rows[index] = row
    return row
end

--- Fills the box for built-in `ring`; hides it while nothing's removed (or `ring` isn't built-in).
function BoxMixin:SetRing(ring)
    local removed = Ring_Data.IsBuiltIn(ring) and Ring_Data.GetRemovedSlices(ring) or {}
    self.ringId = ring and ring.id
    self:SetShown(#removed > 0)
    self.Title:SetText(format(L["Config - Rings - Removed - Title"], #removed))
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

function BoxMixin:Setup()
    self.rows = {}
    self:SetSubcontainer(false)
    self.RestoreAllRow:SetInfo(L["Config - Rings - Removed - All"], nil)
    self.RestoreAllRow:GetButton():SetText(L["Config - Rings - Removed - RestoreAll"])
    self.RestoreAllRow:GetButton():HookClick(function()
        if self.ringId then Ring_Data.RestoreRemoved(self.ringId) end
    end)
    self:Hide()
end

Rings_Removed.Box = UIKit.Template(function(id, name, children, ...)
    local frame =
        Setting_Widgets.ContainerWithTitle(name, {
            -- One row per removed action (GetRow).
            LayoutVertical(name .. ".List")
                :id("List", id)
                :size(UIKit.UI.P_FILL, UIKit.Define.Fit{})
                :layoutSpacing(10)
                :_updateMode(UIKit.Enum.UpdateMode.ChildrenVisibilityChanged),
            Setting_Widgets.ElementButton(name .. ".RestoreAll"):id("RestoreAllRow", id)
        })

    frame.List = UIKit.GetElementById("List", id)
    frame.RestoreAllRow = UIKit.GetElementById("RestoreAllRow", id)
    frame.rowPrefix = name .. ".Row"

    Mixin(frame, BoxMixin)

    return frame
end)
