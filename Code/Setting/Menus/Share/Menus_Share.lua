--[[
    Menus_Share: the Share Menu box of a menu's page in the Menus tab (see Tab.lua), between Menu
    Settings and Delete. Its rows, top to bottom:
        Included Submenus       every submenu that comes along (only when there are some)
        Included Macros         the macros whose text comes along (only when there are some)
        Excluded ...            one per reason (battle pets, deleted macros, others, empty
                                submenus), only when something is left out: what, then the reason
        Click, then Ctrl+C...   "Keybinds aren't shared.", and the share string on the right
    The share string (Menu_Data.BuildShare, the menu and every submenu it contains) is in a
    read-only text box like the Name row's, selected when clicked so Ctrl+C copies it (addons
    can't set the clipboard themselves). It isn't shown for library menus, which fill themselves.
]]

local env = select(2, ...)
local L = env.L
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Setting_Widgets = env.AX_Modules:Import("@\\Setting\\Widgets")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Utils_Text = env.AX_Modules:Import("@\\Utils\\Text")
local Menus_Share = env.AX_Modules:New("@\\Setting\\Menus\\Share")

local format, concat = string.format, table.concat

-- How many reasons can leave something out of a share (one row each, GetExcludedReasons).
local EXCLUDED_ROWS = 4

-- What can be left out of a share, in the order the box shows it. It's built on first use,
-- because Menu_Data loads after the settings.
local excludedReasons

---@return string[] reasons Menu_Data.ShareSkip values
local function GetExcludedReasons()
    excludedReasons = excludedReasons or {
        Menu_Data.ShareSkip.BattlePet, Menu_Data.ShareSkip.MissingMacro,
        Menu_Data.ShareSkip.Invalid, Menu_Data.ShareSkip.Empty,
    }
    return excludedReasons
end

local BoxMixin = {} -- the box keeps its share string (text)

--- Fills the box for `menu` (one of the user's menus, since library menus don't show it).
---@param menu Menu
function BoxMixin:SetMenu(menu)
    local text, summary = Menu_Data.BuildShare({ menu.id })
    self.text = text

    local submenus = {}
    for index, submenuName in ipairs(summary.submenus) do submenus[index] = Utils_Text.Escape(submenuName) end
    self.Includes:SetShown(#submenus > 0)
    self.Includes:SetInfo(format(L["Config - Menus - Share - Includes"], #submenus), concat(submenus, ", "))

    -- Macros travel with their text, so it shows which, and nothing personal is shared by surprise.
    local macros = {}
    for index, macroName in ipairs(summary.macros) do macros[index] = Utils_Text.Escape(macroName) end
    self.Macros:SetShown(#macros > 0)
    self.Macros:SetInfo(format(L["Config - Menus - Share - Macros"], #macros), concat(macros, ", "))

    -- One row per reason something's left out: what, then the reason.
    for index, reason in ipairs(GetExcludedReasons()) do
        local names = {}
        for i, label in ipairs(summary.skippedNames[reason] or {}) do names[i] = Utils_Text.Escape(label) end
        local row = self.Excluded[index]
        row:SetShown(#names > 0)
        -- "Config - Menus - Share - Excluded - <reason>" and its " - Reason", for the reasons above.
        local key = "Config - Menus - Share - Excluded - " .. reason
        -- What, then the reason under it in gold (like the Import page's notes).
        local reasonText = Utils_Text.Gold(format(L[key .. " - Reason"], #names))
        row:SetInfo(format(L[key], #names), concat(names, ", ") .. "\n" .. reasonText)
    end

    -- With every action left out (or none yet), there's no string, and it says why instead.
    if text == "" then
        self.CopyRow:SetInfo(L["Config - Menus - Share - Nothing"], L["Config - Menus - Share - Nothing - Description"])
    else
        self.CopyRow:SetInfo(L["Config - Menus - Share - Hint"], L["Config - Menus - Share - NotShared"])
    end
    self.CopyRow.Input:SetShown(text ~= "")

    local input = self.CopyRow:GetInput()
    input:SetText(text)
    input:SetCursorPosition(0)
    if input:HasFocus() then input:HighlightText() end
end

--- Sets up the box's texts and its read-only copy box.
function BoxMixin:Setup()
    self.text = ""
    self:SetSubcontainer(false)
    self.Title:SetText(L["Config - Menus - Share - Title"])
    -- Lists, with no control on the right, so they wrap at the row's edge.
    self.Includes:SetFullWidth(true)
    self.Macros:SetFullWidth(true)
    for _, row in ipairs(self.Excluded) do row:SetFullWidth(true) end

    -- Read-only: typing or pasting puts the string back, and clicking selects all of it.
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

Menus_Share.Box = UIKit.Template(function(id, name, children, ...)
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
    frame.Excluded = {} -- one per reason (GetExcludedReasons)
    for index = 1, EXCLUDED_ROWS do frame.Excluded[index] = UIKit.GetElementById("Excluded" .. index, id) end
    frame.CopyRow = UIKit.GetElementById("CopyRow", id)

    Mixin(frame, BoxMixin)

    return frame
end)
