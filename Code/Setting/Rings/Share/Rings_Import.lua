--[[
    Rings_Import: the Import page of the Menus tab (the sidebar's Import button, see Tab.lua). It's
    a box to paste a share string, then what's in it (Ring_Data.ReadShare's plan, read as soon as
    it's pasted), Available On, and the Import button (Ring_Data.ApplyShare).
        Menus       a row per menu: the name it imports as, its action count, then in gold what
                    changed (renamed because the name was taken, and skipped actions by reason).
                    Submenus are indented under their menu.
        New Macros  every macro the import creates: its name (in gold under it when renamed),
                    and its text in a read-only box (it runs when used, so the player sees it
                    first). Only when there are some.

    Empty menus were dropped by ReadShare. A string that can't be imported says why under the
    paste box instead. Importing adds new menus only, then opens the first of them.
]]

local env = select(2, ...)
local L = env.L
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local _, _, _, LayoutVertical = unpack(UIKit.UI.Frames)
local Setting_Widgets = env.AX_Modules:Import("@\\Setting\\Widgets")
local ShareString = env.AX_Modules:Import("ax_modules\\share-string")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Utils_Text = env.AX_Modules:Import("@\\Utils\\Text")
local Rings_Common = env.AX_Modules:Import("@\\Setting\\Rings\\Common")
local Rings_Import = env.AX_Modules:New("@\\Setting\\Rings\\Import")

local format = string.format

--- A menu's skipped actions, one line per reason ("1 macro · no free account macro slots").
---@param skipped table<string, integer> counts by Ring_Data.ShareSkip reason
---@return string
local function FormatSkipped(skipped)
    local lines = {}
    for reason, count in pairs(skipped) do
        -- "Config - Rings - Import - Skip - <reason>", one per Ring_Data.ShareSkip (invalid for others).
        local key = "Config - Rings - Import - Skip - " .. reason
        lines[#lines + 1] = format(rawget(L, key) and L[key] or L["Config - Rings - Import - Skip - invalid"], count)
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

--- Why a string can't be imported.
---@param reason string a ShareString.Error or Ring_Data.ShareError value
---@param header table? the string's header, when it could be read
---@return string
local function DescribeRefusal(reason, header)
    if reason == ShareString.Error.OtherGame then
        local game = header and header.game
        -- "Config - Rings - Import - Game - retail" or "- forever" (the game's own name otherwise).
        local key = "Config - Rings - Import - Game - " .. tostring(game)
        local gameName = rawget(L, key) and L[key] or Utils_Text.Escape(game)
        return format(L["Config - Rings - Import - Error - other-game"], gameName)
    end
    -- "Config - Rings - Import - Error - <reason>", one per ShareString.Error and
    -- Ring_Data.ShareError (invalid for others).
    local key = "Config - Rings - Import - Error - " .. tostring(reason)
    return rawget(L, key) and L[key] or L["Config - Rings - Import - Error - invalid"]
end

--- The plan's menus in table order, each with its indent: every top menu, then the menus under
--- it (one level of indent however deep, since the tree would get too wide).
---@param plan table Ring_Data.ReadShare's
---@return { index: integer, indent: integer }[]
local function GetMenuOrder(plan)
    local function Top(index)
        while plan.menus[index].parent do index = plan.menus[index].parent end
        return index
    end
    local order = {}
    for index, menu in ipairs(plan.menus) do
        if not menu.parent then
            order[#order + 1] = { index = index, indent = 0 }
            for other, otherMenu in ipairs(plan.menus) do
                if otherMenu.parent and Top(other) == index then
                    order[#order + 1] = { index = other, indent = 1 }
                end
            end
        end
    end
    return order
end

--- A menu's row: its name, then its action count and, in gold, what changed (a new name because
--- the name was taken, and skipped actions by reason).
---@param menu table one of the plan's menus
---@return string name
---@return string description
local function DescribeMenu(menu)
    local lines = { format(L["Config - Rings - Import - Actions"], #menu.slices) }
    if menu.name ~= menu.sourceName then
        local renamed = format(L["Config - Rings - Import - Renamed - Menu"], Utils_Text.Escape(menu.sourceName))
        lines[#lines + 1] = Utils_Text.Gold(renamed)
    end
    local skippedCount = 0
    for _, count in pairs(menu.skipped) do skippedCount = skippedCount + count end
    if skippedCount > 0 then
        local skipped = format(L["Config - Rings - Import - Skipped"], skippedCount) .. "\n" .. FormatSkipped(menu.skipped)
        lines[#lines + 1] = Utils_Text.Gold(skipped)
    end
    return Utils_Text.Escape(menu.name), table.concat(lines, "\n")
end

local PanelMixin = {}

--- Menu row `index`, made on first use.
---@param index integer
---@return table
function PanelMixin:GetMenuRow(index)
    local row = self.menuRows[index]
    if row then return row end
    row = Setting_Widgets.ElementText(self.namePrefix .. ".MenuRow" .. index)
    row:parent(self.Menus.Content)
    row:SetFullWidth(true) -- nothing on the right, so the text runs to the row's edge
    row:_Render()
    self.menuRows[index] = row
    return row
end

--- Macro row `index`, made on first use.
---@param index integer
---@return table
function PanelMixin:GetMacroRow(index)
    local row = self.macroRows[index]
    if row then return row end
    row = Setting_Widgets.ElementCode(self.namePrefix .. ".MacroRow" .. index)
    row.onResize = self.render -- its box got wider or narrower, so the text wraps differently
    row:parent(self.Macros.Content)
    row:_Render()
    self.macroRows[index] = row
    return row
end

--- Shows the plan's menus.
---@param plan table
function PanelMixin:ShowMenus(plan)
    local order = GetMenuOrder(plan)
    for position, entry in ipairs(order) do
        local row = self:GetMenuRow(position)
        row:SetInfo(DescribeMenu(plan.menus[entry.index]))
        row:SetIndent(entry.indent)
        row:Show()
    end
    for position = #order + 1, #self.menuRows do self.menuRows[position]:Hide() end
end

--- Shows the macros the plan creates.
---@param plan table
function PanelMixin:ShowMacros(plan)
    for index, macro in ipairs(plan.macros) do
        local row = self:GetMacroRow(index)
        -- Its name, and in gold why it's a new one (the name was taken).
        local renamed = macro.name ~= macro.sourceName and Utils_Text.Gold(
            format(L["Config - Rings - Import - Renamed - Macro"], Utils_Text.Escape(macro.sourceName))) or nil
        row:SetInfo(Utils_Text.Escape(macro.name), renamed)
        row:SetCode(macro.body)
        row:Show()
    end
    for index = #plan.macros + 1, #self.macroRows do self.macroRows[index]:Hide() end
    self.Macros:SetShown(#plan.macros > 0)
end

--- Reads the pasted text again (pasted, data changed, page shown) and fills the page.
function PanelMixin:Refresh()
    local text = strtrim(self.PasteRow:GetInput():GetText() or "")
    local plan, reason, header
    if text ~= "" then plan, reason, header = Ring_Data.ReadShare(text) end

    self.ErrorRow:SetShown(text ~= "" and not plan)
    if text ~= "" and not plan then self.ErrorRow:SetInfo(Utils_Text.Gold(DescribeRefusal(reason, header))) end

    self.Menus:SetShown(plan ~= nil)
    self.Macros:SetShown(false)
    self.Confirm:SetShown(plan ~= nil)
    if plan then
        self:ShowMenus(plan)
        self:ShowMacros(plan)
        self.ImportRow:GetButton():SetText(format(L["Config - Rings - Import - Button"], #plan.menus))
    end
end

--- Imports the pasted menus, then opens the first.
function PanelMixin:DoImport()
    -- It reads the string again, because macros made since the paste change the names and the
    -- free macro slots (the page isn't told), and creating a macro with no slot left is an error.
    local plan = Ring_Data.ReadShare(strtrim(self.PasteRow:GetInput():GetText() or ""))
    if not plan then return end
    local scope = Ring_Data.ScopeOrder[self.ScopeRow:GetButtonSelectionMenu():GetValue() or 1] or Ring_Data.Scope.Account
    local ok, result = Ring_Data.ApplyShare(plan, scope)
    if not ok then
        env.Print(L["Config - Rings - Import - Combat"])
        return
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    env.Print(format(L["Config - Rings - Import - Done"], #result))
    self.PasteRow:GetInput():SetText("")
    self.PasteRow:GetInput():ClearFocus()
    if self.onImported then self.onImported(result) end
end

--- Empties the form: no string, and Available On back to Account.
function PanelMixin:Clear()
    self.PasteRow:GetInput():SetText("") -- refreshes the page (OnTextChanged)
    self.ScopeRow:GetButtonSelectionMenu():SetValue(1)
end

--- Puts the cursor in the paste box (the page was just opened).
function PanelMixin:FocusPaste()
    self.PasteRow:GetInput():SetFocus()
end

--- The page was hidden, so the paste box lets go of the keyboard.
function PanelMixin:OnHide()
    self.PasteRow:GetInput():ClearFocus()
end

--- Sets up the page's texts and handlers.
---@param render function renders the tab again after the page changes height
---@param onImported fun(rings: Ring[]) called with the menus just created
function PanelMixin:Setup(render, onImported)
    self.render, self.onImported = render, onImported
    self.menuRows, self.macroRows = {}, {}

    self.Paste:SetSubcontainer(false)
    self.Paste.Title:SetText(L["Config - Rings - Import - Title"])
    self.PasteRow:SetInfo(L["Config - Rings - Import - Paste"], nil)
    self.ErrorRow:SetFullWidth(true)
    self.ErrorRow:Hide()

    self.Menus:SetSubcontainer(false)
    self.Menus.Title:SetText(L["Config - Rings - Import - Menus"])

    self.Macros:SetSubcontainer(false)
    self.Macros.Title:SetText(L["Config - Rings - Import - Macros"])

    self.Confirm:SetSubcontainer(false)

    local input = self.PasteRow:GetInput()
    input:SetMaxLetters(0)
    input:HookScript("OnTextChanged", function()
        self:Refresh()
        self.render()
    end)
    input:HookScript("OnEscapePressed", function(box) box:ClearFocus() end)
    input:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
    -- Clicking selects all of it, so a new paste replaces the old string.
    input:HookScript("OnEditFocusGained", function(box) box:HighlightText() end)
    -- Clicks land on the box's click area (it focuses the box), not the edit box itself.
    self.PasteRow.Input.HitRect:AddOnMouseUp(function() input:HighlightText() end)

    self.ScopeRow:SetInfo(L["Config - Rings - Scope"], L["Config - Rings - Scope - Description"])
    Rings_Common.SetupScopeMenu(self.ScopeRow):SetValue(1)

    self.ImportRow:SetInfo(L["Config - Rings - Import - Confirm"], L["Config - Rings - Import - Confirm - Description"])
    self.ImportRow:GetButton():HookClick(function() self:DoImport() end)

    self.Menus:Hide()
    self.Macros:Hide()
    self.Confirm:Hide()
end

Rings_Import.Panel = UIKit.Template(function(id, name, children, ...)
    local frame =
        LayoutVertical(name, {
            Setting_Widgets.ContainerWithTitle(name .. ".Paste", {
                Setting_Widgets.ElementInput(name .. ".PasteRow"):id("PasteRow", id),
                Setting_Widgets.ElementText(name .. ".Error"):id("ErrorRow", id)
            })
                :id("Paste", id),

            Setting_Widgets.ContainerWithTitle(name .. ".Menus", {})
                :id("Menus", id),

            Setting_Widgets.ContainerWithTitle(name .. ".Macros", {})
                :id("Macros", id),

            Setting_Widgets.Container(name .. ".Confirm", {
                Setting_Widgets.ElementSelectionMenu(name .. ".Scope"):id("ScopeRow", id),
                Setting_Widgets.ElementButton(name .. ".Import"):id("ImportRow", id)
            })
                :id("Confirm", id)
        })
        :size(UIKit.UI.P_FILL, UIKit.Define.Fit{})
        :layoutSpacing(10)
        :_updateMode(UIKit.Enum.UpdateMode.ChildrenVisibilityChanged)

    frame.Paste = UIKit.GetElementById("Paste", id)
    frame.PasteRow = UIKit.GetElementById("PasteRow", id)
    frame.ErrorRow = UIKit.GetElementById("ErrorRow", id)
    frame.Menus = UIKit.GetElementById("Menus", id)
    frame.Macros = UIKit.GetElementById("Macros", id)
    frame.Confirm = UIKit.GetElementById("Confirm", id)
    frame.ScopeRow = UIKit.GetElementById("ScopeRow", id)
    frame.ImportRow = UIKit.GetElementById("ImportRow", id)
    frame.namePrefix = name

    Mixin(frame, PanelMixin)
    frame:HookScript("OnHide", frame.OnHide)

    return frame
end)
