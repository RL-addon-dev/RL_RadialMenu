--[[
    Rings_Tab (see Tab.lua): the Menu Settings rows (Name, Keybind with its capture, Available On)
    and the Delete box.
]]

local env = select(2, ...)
local L = env.L
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Crossbar = env.AX_Modules:Await("@\\Ring\\Crossbar")
local Rings_Keybind = env.AX_Modules:Import("@\\Setting\\Rings\\Keybind")
local Rings_Common = env.AX_Modules:Import("@\\Setting\\Rings\\Common")
local Private = env.AX_Modules:Import("@\\Setting\\Rings\\Tab\\Private")
local Utils_Text = env.AX_Modules:Import("@\\Utils\\Text")

local format = string.format

local PageMixin = Private.PageMixin

-- The controller buttons the keybind help shows: the crossbar and targeting modifiers where
-- they're bound (the gamepad UI's defaults otherwise), and A, B, X and Y.
local DEFAULT_LEFT_MODIFIER, DEFAULT_RIGHT_MODIFIER = "PADLTRIGGER", "PADRTRIGGER"
local DEFAULT_LEFT_TARGETING, DEFAULT_RIGHT_TARGETING = "PADLSHOULDER", "PADRSHOULDER"
local FACE_BUTTONS = { "PAD1", "PAD2", "PAD3", "PAD4" }

local SettingFrame = _G[Setting_Preload.FRAME_NAME]

--- How to set a keybind. Controller buttons are only mentioned while they can be captured
--- (env.IsGamepadUI): then the buttons for combinations (the crossbar modifiers) and the reserved
--- ones (the targeting modifiers, and A, B, X and Y alone), as icons.
---@return string
local function KeybindDescription()
    if not env.IsGamepadUI() then return L["Config - Rings - Keybind - Description"] end
    local function Bound(binding, default)
        return Rings_Keybind.GetDisplayText(Ring_Crossbar.GetBoundKey(binding) or default)
    end
    local faces = {}
    for index, button in ipairs(FACE_BUTTONS) do faces[index] = Rings_Keybind.GetDisplayText(button) end
    return format(L["Config - Rings - Keybind - Description - Controller"],
        Bound(Ring_Crossbar.Binding.LeftModifier, DEFAULT_LEFT_MODIFIER),
        Bound(Ring_Crossbar.Binding.RightModifier, DEFAULT_RIGHT_MODIFIER),
        Bound(Ring_Crossbar.Binding.LeftTargeting, DEFAULT_LEFT_TARGETING),
        Bound(Ring_Crossbar.Binding.RightTargeting, DEFAULT_RIGHT_TARGETING),
        unpack(faces))
end



--- Fills the rows for `ring` (called by RefreshSettings). `isUpdating` keeps the rows' change
--- handlers from treating this as the user's edit.
---@param ring Ring
function PageMixin:RefreshSettingRows(ring)
    self.isUpdating = true

    -- Built-in menus (Quest Items) keep their name and stay on all characters, and can't be deleted.
    local builtIn = Ring_Data.IsBuiltIn(ring)
    -- A menu that lives elsewhere (another class's or character's) is shown, not edited (and has
    -- no Available On, since it isn't this character's).
    local elsewhere = self:GetSelectedElsewhere()
    local locked = builtIn or elsewhere ~= nil

    local nameInput = self.NameRow:GetInput()
    if locked and nameInput:HasFocus() then nameInput:ClearFocus() end
    if not nameInput:HasFocus() then nameInput:SetText(ring.name) end
    self.NameRow.Input:SetEnabled(not locked)
    nameInput:SetEnabled(not locked)

    self:RefreshKeybindRow(ring)
    self.KeybindRow:GetButton():SetEnabled(elsewhere == nil)

    self.ScopeRow:SetShown(elsewhere == nil)
    local _, scope = Ring_Data.GetRing(ring.id)
    local scopeMenu = self.ScopeRow:GetButtonSelectionMenu()
    scopeMenu:SetValue(tIndexOf(Ring_Data.ScopeOrder, scope) or 1)
    scopeMenu:SetEnabled(not builtIn)

    self.DeleteRow:GetButton():SetEnabled(not builtIn)
    self.DeleteRow:SetInfo(L["Config - Rings - Delete"], builtIn and L["Config - Rings - Delete - BuiltIn"] or L["Config - Rings - Delete - Description"])

    self.isUpdating = false
end



-- Name and scope

--- Saves the name typed in the Name row (or puts the old one back when it's empty).
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

--- Available On was changed to scope `index` (in Ring_Data.ScopeOrder).
---@param index integer
function PageMixin:OnScopeChanged(index)
    if self.isUpdating then return end
    local ring = self:GetSelectedRing()
    if not ring then return end
    if Ring_Data.IsBuiltIn(ring) then
        -- Built-in menus stay account-wide, so every character has one.
        env.Print(L["Config - Rings - Scope - BuiltIn"])
        self:RefreshSettings()
        return
    end
    Ring_Data.SetScope(ring.id, Ring_Data.ScopeOrder[index])
    self:RevealInMyMenus(ring.id) -- it moved to another group, so that one opens
end



-- Keybind

--- Fills the Keybind row: the key, and where it's saved, its conflicts and overrides.
---@param ring Ring
function PageMixin:RefreshKeybindRow(ring)
    local button = self.KeybindRow:GetButton()
    if self.capturingRingId == ring.id and Rings_Keybind.IsCapturing() then
        button:SetText(L["Config - Rings - Keybind - Capturing"])
        return
    end

    -- For a menu that lives elsewhere, its keybind there, whose it is, and how to change or use it.
    local elsewhere = self:GetSelectedElsewhere()
    if elsewhere then
        button:SetText(elsewhere.key and Rings_Keybind.GetDisplayText(elsewhere.key) or L["Config - Rings - Keybind - NotBound"])
        local note
        if elsewhere.character then
            local character = elsewhere.character
            note = format(L["Config - Rings - OtherCharacter - Description"], character.name or "?",
                character.updated and date("%Y-%m-%d", character.updated) or "?", character.name or "?")
        else
            note = format(L["Config - Rings - OtherClass - Description"], Rings_Common.GetClassName(elsewhere.class))
        end
        self.KeybindRow:SetInfo(L["Config - Rings - Keybind"], Utils_Text.Gold(note))
        return
    end

    local key = Ring_Data.GetBinding(ring.id)
    button:SetText(key and Rings_Keybind.GetDisplayText(key) or L["Config - Rings - Keybind - NotBound"])

    -- Where the keybind is saved follows Available On. It warns when the key also has a Blizzard
    -- keybinding (the menu's override wins while bound).
    local _, scope = Ring_Data.GetRing(ring.id)
    -- "Config - Rings - Keybind - Account", "- Class" or "- Character".
    local savedKey = "Config - Rings - Keybind - " .. Rings_Common.GetScopeKeyName(scope)
    local description = format(L[savedKey], Ring_Data.GetScopeWhere(scope)) .. " " .. KeybindDescription()
    local conflict = key and Rings_Keybind.GetBlizzardConflict(key)
    if conflict then
        description = description .. "\n" .. Utils_Text.Gold(format(L["Config - Rings - Keybind - Conflict"], conflict))
    end
    for _, override in ipairs(Ring_Data.GetBindingOverrides(ring.id)) do
        description = description .. "\n" .. Utils_Text.Gold(format(L["Config - Rings - Keybind - Overridden"],
            Ring_Data.GetScopeWhere(override.scope), override.ring.name))
    end
    self.KeybindRow:SetInfo(L["Config - Rings - Keybind"], description)
end

--- The Keybind button was clicked: a left click starts (or cancels) the capture, and a right
--- click clears the keybind.
---@param mouseButton string?
function PageMixin:OnKeybindClicked(mouseButton)
    local ring = self:GetSelectedRing()
    if not ring or self:GetSelectedElsewhere() then return end

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

--- A key was captured for the menu whose keybind was being set.
---@param key string
function PageMixin:OnKeyCaptured(key)
    local ringId = self.capturingRingId
    self.capturingRingId = nil
    if not ringId then return end

    -- A crossbar combo puts the menu's macro on that crossbar slot, so it asks before replacing
    -- what's there (nothing changes until then).
    local occupant = Ring_Crossbar.IsSlot(key) and Ring_Crossbar.GetOccupant(ringId, key)
    if occupant then
        self:RefreshSettings()
        SettingFrame.Prompt:Open({
            text         = L["Config - Rings - Keybind - Crossbar - Replace"],
            options      = {
                { text = L["Config - Rings - Keybind - Crossbar - Replace - Yes"], callback = function() self:ApplyKeybind(ringId, key) end },
                { text = L["Config - Rings - Keybind - Crossbar - Replace - No"], callback = nil }
            },
            hideOnEscape = true,
            timeout      = 15
        }, Rings_Keybind.GetDisplayText(key), occupant)
        return
    end
    self:ApplyKeybind(ringId, key)
end

--- Saves `key` as menu `ringId`'s keybind, says where it came from, and for a crossbar combo puts
--- the menu's macro on its slot.
---@param ringId string
---@param key string
function PageMixin:ApplyKeybind(ringId, key)
    -- It says where the key came from: menus that lose it (same scope), or a menu of another scope
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
    if Ring_Crossbar.IsSlot(key) then
        local ok, reason = Ring_Crossbar.Place(ringId, key)
        if ok then
            env.Print(format(L["Config - Rings - Keybind - Crossbar - Placed"], keyText, ring.name))
        else
            -- "Config - Rings - Keybind - Crossbar - Error - <reason>", one per Ring_Crossbar.PlaceError.
            env.Print(L["Config - Rings - Keybind - Crossbar - Error - " .. reason])
        end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end



-- Delete

--- Asks before deleting the selected menu.
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

--- Sets up the rows' texts and handlers.
---@param page table
function Private.SetupSettingRows(page)
    page.NameRow:SetInfo(L["Config - Rings - Name"], nil)
    local nameInput = page.NameRow:GetInput()
    nameInput:HookScript("OnEnterPressed", function(input)
        page:CommitName()
        input:ClearFocus()
    end)
    nameInput:HookScript("OnEditFocusLost", function() page:CommitName() end)

    page.KeybindRow:SetInfo(L["Config - Rings - Keybind"], KeybindDescription())
    local keybindButton = page.KeybindRow:GetButton()
    -- It remembers which mouse button pressed it, since a right click clears instead of capturing.
    keybindButton:HookScript("OnMouseDown", function(_, mouseButton) keybindButton.lastMouseButton = mouseButton end)
    keybindButton:HookClick(function() page:OnKeybindClicked(keybindButton.lastMouseButton) end)

    page.ScopeRow:SetInfo(L["Config - Rings - Scope"], L["Config - Rings - Scope - Description"])
    local scopeMenu = Rings_Common.SetupScopeMenu(page.ScopeRow)
    scopeMenu:HookValueChanged(function(_, index) page:OnScopeChanged(index) end)

    page.DeleteRow:SetInfo(L["Config - Rings - Delete"], L["Config - Rings - Delete - Description"])
    page.DeleteRow:GetButton():SetText(L["Config - Rings - Delete - Button"])
    page.DeleteRow:GetButton():HookClick(function() page:ConfirmDeleteRing() end)
end
