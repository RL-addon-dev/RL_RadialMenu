--[[
    Menus_Tab (see Tab.lua): the Menu Settings rows (Name, Keybind with its capture, Available On)
    and the Delete box.
]]

local env = select(2, ...)
local L = env.L
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Menu_Crossbar = env.AX_Modules:Await("@\\Menu\\Crossbar")
local Menus_Keybind = env.AX_Modules:Import("@\\Setting\\Menus\\Keybind")
local Menus_Common = env.AX_Modules:Import("@\\Setting\\Menus\\Common")
local Private = env.AX_Modules:Import("@\\Setting\\Menus\\Tab\\Private")
local Utils_Text = env.AX_Modules:Import("@\\Utils\\Text")

local format = string.format

local PageMixin = Private.PageMixin

-- The face buttons the keybind help shows (A, B, X and Y).
local FACE_BUTTONS = { "PAD1", "PAD2", "PAD3", "PAD4" }

local SettingFrame = _G[Setting_Preload.FRAME_NAME]

--- How to set a keybind. Controller buttons are only mentioned while they can be captured
--- (env.IsGamepadUI): then the buttons for combinations (the crossbar modifiers) and the reserved
--- ones (the targeting modifiers, and A, B, X and Y alone), as icons.
---@return string
local function KeybindDescription()
    if not env.IsGamepadUI() then return L["Config - Menus - Keybind - Description"] end
    local function Bound(binding)
        return Menus_Keybind.GetDisplayText(Menu_Crossbar.GetBoundKey(binding) --[[@as string]])
    end
    local faces = {}
    for index, button in ipairs(FACE_BUTTONS) do faces[index] = Menus_Keybind.GetDisplayText(button) end
    return format(L["Config - Menus - Keybind - Description - Controller"],
        Bound(Menu_Crossbar.Binding.LeftModifier),
        Bound(Menu_Crossbar.Binding.RightModifier),
        Bound(Menu_Crossbar.Binding.LeftTargeting),
        Bound(Menu_Crossbar.Binding.RightTargeting),
        unpack(faces))
end



--- Fills the rows for `menu` (called by RefreshSettings). `isUpdating` keeps the rows' change
--- handlers from treating this as the user's edit.
---@param menu Menu
function PageMixin:RefreshSettingRows(menu)
    self.isUpdating = true

    -- Library menus (Quest Items) keep their name and stay on all characters, and can't be deleted.
    local library = Menu_Data.IsLibraryMenu(menu)
    -- A menu that lives elsewhere (another class's or character's) is shown, not edited (and has
    -- no Available On, since it isn't this character's).
    local elsewhere = self:GetSelectedElsewhere()
    local locked = library or elsewhere ~= nil

    local nameInput = self.NameRow:GetInput()
    if locked and nameInput:HasFocus() then nameInput:ClearFocus() end
    if not nameInput:HasFocus() then nameInput:SetText(menu.name) end
    self.NameRow.Input:SetEnabled(not locked)
    nameInput:SetEnabled(not locked)

    self:RefreshKeybindRow(menu)
    self.KeybindRow:GetButton():SetEnabled(elsewhere == nil)

    self.ScopeRow:SetShown(elsewhere == nil)
    local _, scope = Menu_Data.GetMenu(menu.id)
    local scopeMenu = self.ScopeRow:GetButtonSelectionMenu()
    scopeMenu:SetValue(tIndexOf(Menu_Data.ScopeOrder, scope) or 1)
    scopeMenu:SetEnabled(not library)

    self.DeleteRow:GetButton():SetEnabled(not library)
    self.DeleteRow:SetInfo(L["Config - Menus - Delete"], library and L["Config - Menus - Delete - Library"] or L["Config - Menus - Delete - Description"])

    self.isUpdating = false
end



-- Name and scope

--- Saves the name typed in the Name row (or puts the old one back when it's empty).
function PageMixin:CommitName()
    local menu = self:GetSelectedMenu()
    if not menu or Menu_Data.IsLibraryMenu(menu) then return end

    local name = strtrim(self.NameRow:GetInput():GetText() or "")
    if name == "" then
        self.NameRow:GetInput():SetText(menu.name)
    elseif name ~= menu.name then
        Menu_Data.RenameMenu(menu.id, name)
    end
end

--- Available On was changed to scope `index` (in Menu_Data.ScopeOrder).
---@param index integer
function PageMixin:OnScopeChanged(index)
    if self.isUpdating then return end
    local menu = self:GetSelectedMenu()
    if not menu then return end
    if Menu_Data.IsLibraryMenu(menu) then
        -- Library menus stay account-wide, so every character has one.
        env.Print(L["Config - Menus - Scope - Library"])
        self:RefreshSettings()
        return
    end
    Menu_Data.SetScope(menu.id, Menu_Data.ScopeOrder[index])
    self:RevealInMyMenus(menu.id) -- it moved to another group, so that one opens
end



-- Keybind

--- Fills the Keybind row: the key, and where it's saved, its conflicts and overrides.
---@param menu Menu
function PageMixin:RefreshKeybindRow(menu)
    local button = self.KeybindRow:GetButton()
    if self.capturingMenuId == menu.id and Menus_Keybind.IsCapturing() then
        button:SetText(L["Config - Menus - Keybind - Capturing"])
        return
    end

    -- For a menu that lives elsewhere, its keybind there, whose it is, and how to change or use it.
    local elsewhere = self:GetSelectedElsewhere()
    if elsewhere then
        button:SetText(elsewhere.key and Menus_Keybind.GetDisplayText(elsewhere.key) or L["Config - Menus - Keybind - NotBound"])
        local note
        if elsewhere.character then
            local character = elsewhere.character
            note = format(L["Config - Menus - OtherCharacter - Description"], character.name or "?",
                character.updated and date("%Y-%m-%d", character.updated) or "?", character.name or "?")
        else
            note = format(L["Config - Menus - OtherClass - Description"], Menus_Common.GetClassName(elsewhere.class))
        end
        self.KeybindRow:SetInfo(L["Config - Menus - Keybind"], Utils_Text.Gold(note))
        return
    end

    local key = Menu_Data.GetBinding(menu.id)
    button:SetText(key and Menus_Keybind.GetDisplayText(key) or L["Config - Menus - Keybind - NotBound"])

    -- Where the keybind is saved follows Available On. It warns when the key also has a Blizzard
    -- keybinding (the menu's override wins while bound).
    local _, scope = Menu_Data.GetMenu(menu.id)
    -- "Config - Menus - Keybind - Account", "- Class" or "- Character".
    local savedKey = "Config - Menus - Keybind - " .. Menus_Common.GetScopeKeyName(scope)
    local description = format(L[savedKey], Menu_Data.GetScopeWhere(scope)) .. " " .. KeybindDescription()
    local conflict = key and Menus_Keybind.GetBlizzardConflict(key)
    if conflict then
        description = description .. "\n" .. Utils_Text.Gold(format(L["Config - Menus - Keybind - Conflict"], conflict))
    end
    for _, override in ipairs(Menu_Data.GetBindingOverrides(menu.id)) do
        description = description .. "\n" .. Utils_Text.Gold(format(L["Config - Menus - Keybind - Overridden"],
            Menu_Data.GetScopeWhere(override.scope), override.menu.name))
    end
    self.KeybindRow:SetInfo(L["Config - Menus - Keybind"], description)
end

--- The Keybind button was clicked: a left click starts (or cancels) the capture, and a right
--- click clears the keybind.
---@param mouseButton string?
function PageMixin:OnKeybindClicked(mouseButton)
    local menu = self:GetSelectedMenu()
    if not menu or self:GetSelectedElsewhere() then return end

    if mouseButton == "RightButton" then
        Menus_Keybind.CancelCapture()
        if Menu_Data.GetBinding(menu.id) then Menu_Data.SetBinding(menu.id, nil) end
        return
    end

    -- Clicking again while listening cancels.
    if Menus_Keybind.IsCapturing() then
        Menus_Keybind.CancelCapture()
        return
    end

    -- A focused text box would take the key press instead of the capture.
    self.NameRow:GetInput():ClearFocus()

    local started = Menus_Keybind.StartCapture(
        function(key) self:OnKeyCaptured(key) end,
        function()
            self.capturingMenuId = nil
            self:RefreshSettings()
        end)
    if not started then
        env.Print(L["Config - Menus - Keybind - Combat"])
        return
    end

    self.capturingMenuId = menu.id
    self.KeybindRow:GetButton():SetText(L["Config - Menus - Keybind - Capturing"])
end

--- A key was captured for the menu whose keybind was being set.
---@param key string
function PageMixin:OnKeyCaptured(key)
    local menuId = self.capturingMenuId
    self.capturingMenuId = nil
    if not menuId then return end

    -- A crossbar combo puts the menu's macro on that crossbar slot, so it asks before replacing
    -- what's there (nothing changes until then).
    local occupant = Menu_Crossbar.IsSlot(key) and Menu_Crossbar.GetOccupant(menuId, key)
    if occupant then
        self:RefreshSettings()
        SettingFrame.Prompt:Open({
            text         = L["Config - Menus - Keybind - Crossbar - Replace"],
            options      = {
                { text = L["Config - Menus - Keybind - Crossbar - Replace - Yes"], callback = function() self:ApplyKeybind(menuId, key) end },
                { text = L["Config - Menus - Keybind - Crossbar - Replace - No"], callback = nil }
            },
            hideOnEscape = true,
            timeout      = 15
        }, Menus_Keybind.GetDisplayText(key), occupant)
        return
    end
    self:ApplyKeybind(menuId, key)
end

--- Saves `key` as menu `menuId`'s keybind, says where it came from, and for a crossbar combo puts
--- the menu's macro on its slot.
---@param menuId string
---@param key string
function PageMixin:ApplyKeybind(menuId, key)
    -- It says where the key came from: menus that lose it (same scope), or a menu of another scope
    -- that keeps it (the narrower scope's menu opens where it applies, the other one elsewhere).
    local others = {}
    for _, other in ipairs(Menu_Data.GetMenus()) do
        if other.id ~= menuId and Menu_Data.GetBinding(other.id) == key then others[#others + 1] = other end
    end

    Menu_Data.SetBinding(menuId, key)
    local keyText = Menus_Keybind.GetDisplayText(key)
    local menu, scope = Menu_Data.GetMenu(menuId)
    for _, other in ipairs(others) do
        local otherKey, otherScope = Menu_Data.GetBinding(other.id)
        if otherKey ~= key then
            env.Print(format(L["Config - Menus - Keybind - Moved"], keyText, menu.name, other.name))
        elseif Menu_Data.IsNarrowerScope(scope, otherScope) then
            env.Print(format(L["Config - Menus - Keybind - Overrides"], keyText, menu.name, Menu_Data.GetScopeWhere(scope), other.name))
        else
            env.Print(format(L["Config - Menus - Keybind - OverriddenBy"], keyText, menu.name, Menu_Data.GetScopeWhere(otherScope), other.name))
        end
    end
    if Menu_Crossbar.IsSlot(key) then
        local ok, reason = Menu_Crossbar.Place(menuId, key)
        if ok then
            env.Print(format(L["Config - Menus - Keybind - Crossbar - Placed"], keyText, menu.name))
        else
            -- "Config - Menus - Keybind - Crossbar - Error - <reason>", one per Menu_Crossbar.PlaceError.
            env.Print(L["Config - Menus - Keybind - Crossbar - Error - " .. reason])
        end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end



-- Delete

--- Asks before deleting the selected menu.
function PageMixin:ConfirmDeleteMenu()
    local menu = self:GetSelectedMenu()
    if not menu or Menu_Data.IsLibraryMenu(menu) then return end

    local menuId = menu.id
    SettingFrame.Prompt:Open({
        text         = L["Config - Menus - Delete - Prompt"],
        options      = {
            { text = L["Config - Menus - Delete - Prompt - Yes"], callback = function() Menu_Data.DeleteMenu(menuId) end },
            { text = L["Config - Menus - Delete - Prompt - No"], callback = nil }
        },
        hideOnEscape = true,
        timeout      = 10
    }, menu.name)
end



-- Construction

--- Sets up the rows' texts and handlers.
---@param page table
function Private.SetupSettingRows(page)
    page.NameRow:SetInfo(L["Config - Menus - Name"], nil)
    local nameInput = page.NameRow:GetInput()
    nameInput:HookScript("OnEnterPressed", function(input)
        page:CommitName()
        input:ClearFocus()
    end)
    nameInput:HookScript("OnEditFocusLost", function() page:CommitName() end)

    page.KeybindRow:SetInfo(L["Config - Menus - Keybind"], KeybindDescription())
    local keybindButton = page.KeybindRow:GetButton()
    -- It remembers which mouse button pressed it, since a right click clears instead of capturing.
    keybindButton:HookScript("OnMouseDown", function(_, mouseButton) keybindButton.lastMouseButton = mouseButton end)
    keybindButton:HookClick(function() page:OnKeybindClicked(keybindButton.lastMouseButton) end)

    page.ScopeRow:SetInfo(L["Config - Menus - Scope"], L["Config - Menus - Scope - Description"])
    local scopeMenu = Menus_Common.SetupScopeMenu(page.ScopeRow)
    scopeMenu:HookValueChanged(function(_, index) page:OnScopeChanged(index) end)

    page.DeleteRow:SetInfo(L["Config - Menus - Delete"], L["Config - Menus - Delete - Description"])
    page.DeleteRow:GetButton():SetText(L["Config - Menus - Delete - Button"])
    page.DeleteRow:GetButton():HookClick(function() page:ConfirmDeleteMenu() end)
end
