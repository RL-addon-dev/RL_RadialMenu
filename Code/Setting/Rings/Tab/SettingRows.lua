--[[
    Menus tab: the Ring Settings rows (Name, Keybind with its capture flow, Available On) and
    the Delete box. See Tab.lua.
]]

local env = select(2, ...)
local L = env.L
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Rings_Keybind = env.AX_Modules:Import("@\\Setting\\Rings\\Keybind")
local Private = env.AX_Modules:Import("@\\Setting\\Rings\\Tab\\Private")

local format = string.format
local PageMixin = Private.PageMixin

-- Keybind row: where the keybind is saved, by scope.
local KEYBIND_SAVED = {
    account   = "Config - Rings - Keybind - Account",
    class     = "Config - Rings - Keybind - Class",
    character = "Config - Rings - Keybind - Character",
}

local SettingFrame = _G[Setting_Preload.FRAME_NAME]



--- Fills the rows for `ring` (called by RefreshSettings). `isUpdating` keeps the rows' change
--- handlers from treating this as the user's edit.
function PageMixin:RefreshSettingRows(ring)
    self.isUpdating = true

    -- Built-in rings (Quest Items) keep their name and stay on all characters, and can't be deleted.
    local builtIn = Ring_Data.IsBuiltIn(ring)

    local nameInput = self.NameRow:GetInput()
    if builtIn and nameInput:HasFocus() then nameInput:ClearFocus() end
    if not nameInput:HasFocus() then nameInput:SetText(ring.name) end
    self.NameRow.Input:SetEnabled(not builtIn)
    nameInput:SetEnabled(not builtIn)

    self:RefreshKeybindRow(ring)

    local _, scope = Ring_Data.GetRing(ring.id)
    local scopeMenu = self.ScopeRow:GetButtonSelectionMenu()
    scopeMenu:SetValue(tIndexOf(Ring_Data.ScopeOrder, scope) or 1)
    scopeMenu:SetEnabled(not builtIn)

    self.DeleteRow:GetButton():SetEnabled(not builtIn)
    self.DeleteRow:SetInfo(L["Config - Rings - Delete"], builtIn and L["Config - Rings - Delete - BuiltIn"] or L["Config - Rings - Delete - Description"])

    self.isUpdating = false
end



-- Name and scope

function PageMixin:CommitName()
    local ring = self:GetSelectedRing()
    if not ring or Ring_Data.IsBuiltIn(ring) then return end

    local name = strtrim(self.NameRow:GetInput():GetText() or "")
    if name == "" then
        self.NameRow:GetInput():SetText(ring.name)
    elseif name ~= ring.name then
        Ring_Data.RenameRing(ring.id, name)
    end
end

function PageMixin:OnScopeChanged(index)
    if self.isUpdating then return end
    local ring = self:GetSelectedRing()
    if not ring then return end
    if Ring_Data.IsBuiltIn(ring) then
        -- Built-in rings stay account-wide so every character has one.
        env.Print(L["Config - Rings - Scope - BuiltIn"])
        self:RefreshSettings()
        return
    end
    Ring_Data.SetScope(ring.id, Ring_Data.ScopeOrder[index])
end



-- Keybind

function PageMixin:RefreshKeybindRow(ring)
    local button = self.KeybindRow:GetButton()
    if self.capturingRingId == ring.id and Rings_Keybind.IsCapturing() then
        button:SetText(L["Config - Rings - Keybind - Capturing"])
        return
    end

    local key = Ring_Data.GetBinding(ring.id)
    button:SetText(key and Rings_Keybind.GetDisplayText(key) or L["Config - Rings - Keybind - NotBound"])

    -- Where the keybind is saved follows Available On. Warn when the key also has a Blizzard
    -- keybinding (the menu's override wins while bound).
    local _, scope = Ring_Data.GetRing(ring.id)
    local description = format(L[KEYBIND_SAVED[scope] or KEYBIND_SAVED.account], Ring_Data.GetScopeWhere(scope))
        .. " " .. L["Config - Rings - Keybind - Description"]
    local conflict = key and Rings_Keybind.GetBlizzardConflict(key)
    if conflict then
        description = description .. "\n|cffffd100" .. format(L["Config - Rings - Keybind - Conflict"], conflict) .. "|r"
    end
    for _, override in ipairs(Ring_Data.GetBindingOverrides(ring.id)) do
        description = description .. "\n|cffffd100" .. format(L["Config - Rings - Keybind - Overridden"], Ring_Data.GetScopeWhere(override.scope), override.ring.name) .. "|r"
    end
    self.KeybindRow:SetInfo(L["Config - Rings - Keybind"], description)
end

function PageMixin:OnKeybindClicked(mouseButton)
    local ring = self:GetSelectedRing()
    if not ring then return end

    if mouseButton == "RightButton" then
        Rings_Keybind.CancelCapture()
        if Ring_Data.GetBinding(ring.id) then Ring_Data.SetBinding(ring.id, nil) end
        return
    end

    -- Clicking again while listening cancels.
    if Rings_Keybind.IsCapturing() then
        Rings_Keybind.CancelCapture()
        return
    end

    -- A focused text box would take the key press instead of the capture.
    self.NameRow:GetInput():ClearFocus()

    local started = Rings_Keybind.StartCapture(
        function(key) self:OnKeyCaptured(key) end,
        function()
            self.capturingRingId = nil
            self:RefreshSettings()
        end)
    if not started then
        env.Print(L["Config - Rings - Keybind - Combat"])
        return
    end

    self.capturingRingId = ring.id
    self.KeybindRow:GetButton():SetText(L["Config - Rings - Keybind - Capturing"])
end

function PageMixin:OnKeyCaptured(key)
    local ringId = self.capturingRingId
    self.capturingRingId = nil
    if not ringId then return end

    -- Say where the key came from: menus that lose it (same scope), or a menu of another scope
    -- that keeps it (the narrower scope's menu opens where it applies, the other one elsewhere).
    local others = {}
    for _, other in ipairs(Ring_Data.GetRings()) do
        if other.id ~= ringId and Ring_Data.GetBinding(other.id) == key then others[#others + 1] = other end
    end

    Ring_Data.SetBinding(ringId, key)
    local keyText = Rings_Keybind.GetDisplayText(key)
    local ring, scope = Ring_Data.GetRing(ringId)
    for _, other in ipairs(others) do
        local otherKey, otherScope = Ring_Data.GetBinding(other.id)
        if otherKey ~= key then
            env.Print(format(L["Config - Rings - Keybind - Moved"], keyText, ring.name, other.name))
        elseif Ring_Data.IsNarrowerScope(scope, otherScope) then
            env.Print(format(L["Config - Rings - Keybind - Overrides"], keyText, ring.name, Ring_Data.GetScopeWhere(scope), other.name))
        else
            env.Print(format(L["Config - Rings - Keybind - OverriddenBy"], keyText, ring.name, Ring_Data.GetScopeWhere(otherScope), other.name))
        end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end



-- Delete

function PageMixin:ConfirmDeleteRing()
    local ring = self:GetSelectedRing()
    if not ring or Ring_Data.IsBuiltIn(ring) then return end

    local ringId = ring.id
    SettingFrame.Prompt:Open({
        text         = L["Config - Rings - Delete - Prompt"],
        options      = {
            { text = L["Config - Rings - Delete - Prompt - Yes"], callback = function() Ring_Data.DeleteRing(ringId) end },
            { text = L["Config - Rings - Delete - Prompt - No"], callback = nil }
        },
        hideOnEscape = true,
        timeout      = 10
    }, ring.name)
end



-- Construction

function Private.SetupSettingRows(page)
    local selectionMenu = SettingFrame.SelectionMenu

    page.NameRow:SetInfo(L["Config - Rings - Name"], nil)
    local nameInput = page.NameRow:GetInput()
    nameInput:HookScript("OnEnterPressed", function(input)
        page:CommitName()
        input:ClearFocus()
    end)
    nameInput:HookScript("OnEditFocusLost", function() page:CommitName() end)

    page.KeybindRow:SetInfo(L["Config - Rings - Keybind"], L["Config - Rings - Keybind - Description"])
    local keybindButton = page.KeybindRow:GetButton()
    -- Remember which mouse button pressed it: right-click clears instead of capturing.
    keybindButton:HookScript("OnMouseDown", function(_, mouseButton) keybindButton.lastMouseButton = mouseButton end)
    keybindButton:HookClick(function() page:OnKeybindClicked(keybindButton.lastMouseButton) end)

    page.ScopeRow:SetInfo(L["Config - Rings - Scope"], L["Config - Rings - Scope - Description"])
    local scopeMenu = page.ScopeRow:GetButtonSelectionMenu()
    scopeMenu:SetSelectionMenu(selectionMenu)
    local scopeNames = {}
    for index, scope in ipairs(Ring_Data.ScopeOrder) do scopeNames[index] = Ring_Data.GetScopeName(scope) end
    scopeMenu:SetData(scopeNames)
    scopeMenu:HookValueChanged(function(_, index) page:OnScopeChanged(index) end)

    page.DeleteRow:SetInfo(L["Config - Rings - Delete"], L["Config - Rings - Delete - Description"])
    page.DeleteRow:GetButton():SetText(L["Config - Rings - Delete - Button"])
    page.DeleteRow:GetButton():HookClick(function() page:ConfirmDeleteRing() end)
end
