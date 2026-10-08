--[[
    Share Menu box of a menu's page in the Menus tab (see Tab.lua), between Menu Settings and
    Delete. Rows, top to bottom:
        Included Submenus       every submenu that comes along (only when there are some)
        Included Macros         the macros whose text comes along (only when there are some)
        Excluded ...            per reason (battle pets, deleted macros, others, empty
                                submenus), only when something is left out: what, then the reason
        Click, then Ctrl+C...   "Keybinds aren't shared.", and the share string on the right
    The share string (Ring_Data.BuildShare: the menu and every submenu it contains) is in a
    read-only text box like the Name row's, selected when clicked so Ctrl+C copies it (addons
    can't set the clipboard themselves). Not shown for built-in menus (they fill themselves).
]]

local env = select(2, ...)
local L = env.L
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Setting_Widgets = env.AX_Modules:Import("@\\Setting\\Widgets")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Rings_Share = env.AX_Modules:New("@\\Setting\\Rings\\Share")

local format, concat = string.format, table.concat

-- What can be left out of a share (Ring_Data.ShareSkip), in the order the box shows it.
local EXCLUDED_REASONS = { "battlepet", "missing-macro", "invalid", "empty" }
local REASON_COLOR = "|cffffd100"

--- Text as it is, not as UI escape codes (menu names are the player's own text).
local function Plain(text)
    return (tostring(text or ""):gsub("|", "||"))
end

local BoxMixin = {}

--- Fills the box for `ring` (a user menu: built-ins don't show it).
function BoxMixin:SetRing(ring)
    local text, summary = Ring_Data.BuildShare({ ring.id })
    self.text = text

    local submenus = {}
    for index, submenuName in ipairs(summary.submenus) do submenus[index] = Plain(submenuName) end
    self.Includes:SetShown(#submenus > 0)
    self.Includes:SetInfo(format(L["Config - Rings - Share - Includes"], #submenus), concat(submenus, ", "))

    -- Macros travel with their text: show which, so nothing personal is shared by surprise.
    local macros = {}
    for index, macroName in ipairs(summary.macros) do macros[index] = Plain(macroName) end
    self.Macros:SetShown(#macros > 0)
    self.Macros:SetInfo(format(L["Config - Rings - Share - Macros"], #macros), concat(macros, ", "))

    -- One row per reason something's left out: what, then the reason.
    for index, reason in ipairs(EXCLUDED_REASONS) do
        local names = {}
        for i, label in ipairs(summary.skippedNames[reason] or {}) do names[i] = Plain(label) end
        local row = self.Excluded[index]
        row:SetShown(#names > 0)
        local key = "Config - Rings - Share - Excluded - " .. reason
        -- What, then the reason under it in yellow (like the Import page's notes).
        row:SetInfo(format(L[key], #names), concat(names, ", ") .. "\n" .. REASON_COLOR .. format(L[key .. " - Reason"], #names) .. "|r")
    end

    -- Every action left out (or none yet): no string, say why instead.
    if text == "" then
        self.CopyRow:SetInfo(L["Config - Rings - Share - Nothing"], L["Config - Rings - Share - Nothing - Description"])
    else
        self.CopyRow:SetInfo(L["Config - Rings - Share - Hint"], L["Config - Rings - Share - NotShared"])
    end
    self.CopyRow.Input:SetShown(text ~= "")

    local input = self.CopyRow:GetInput()
    input:SetText(text)
    input:SetCursorPosition(0)
    if input:HasFocus() then input:HighlightText() end
end

function BoxMixin:Setup()
    self.text = ""
    self:SetSubcontainer(false)
    self.Title:SetText(L["Config - Rings - Share - Title"])
    -- Lists, no control on the right: wrap at the row's edge.
    self.Includes:SetFullWidth(true)
    self.Macros:SetFullWidth(true)
    for _, row in ipairs(self.Excluded) do row:SetFullWidth(true) end

    -- Read-only: typing or pasting puts the string back; clicking selects all of it.
    local input = self.CopyRow:GetInput()
    input:SetMaxLetters(0)
    input:HookScript("OnTextChanged", function(box, userInput)
        if not userInput then return end
        box:SetText(self.text)
        box:HighlightText()
    end)
    input:HookScript("OnEditFocusGained", function(box) box:HighlightText() end)
    -- Clicks inside it too (they land on the box's click area, which focuses it).
    self.CopyRow.Input.HitRect:AddOnMouseUp(function() input:HighlightText() end)
    input:HookScript("OnEscapePressed", function(box) box:ClearFocus() end)
    input:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
    self:HookScript("OnHide", function() input:ClearFocus() end)
end

Rings_Share.Box = UIKit.Template(function(id, name, children, ...)
    local frame =
        Setting_Widgets.ContainerWithTitle(name, {
            Setting_Widgets.ElementText(name .. ".Includes"):id("Includes", id),
            Setting_Widgets.ElementText(name .. ".Macros"):id("Macros", id),
            Setting_Widgets.ElementText(name .. ".Excluded1"):id("Excluded1", id),
            Setting_Widgets.ElementText(name .. ".Excluded2"):id("Excluded2", id),
            Setting_Widgets.ElementText(name .. ".Excluded3"):id("Excluded3", id),
            Setting_Widgets.ElementText(name .. ".Excluded4"):id("Excluded4", id),
            Setting_Widgets.ElementInput(name .. ".Copy"):id("CopyRow", id)
        })

    frame.Includes = UIKit.GetElementById("Includes", id)
    frame.Macros = UIKit.GetElementById("Macros", id)
    frame.Excluded = {} -- one per EXCLUDED_REASONS
    for index in ipairs(EXCLUDED_REASONS) do frame.Excluded[index] = UIKit.GetElementById("Excluded" .. index, id) end
    frame.CopyRow = UIKit.GetElementById("CopyRow", id)

    Mixin(frame, BoxMixin)

    return frame
end)
