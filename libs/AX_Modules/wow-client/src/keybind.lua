local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local LazyTimer = env.AX_Modules:Import("ax_modules\\lazy-timer")
local WoWClient_Events = env.AX_Modules:Import("ax_modules\\wow-client\\events")
local WoWClient_Keybind = env.AX_Modules:New("ax_modules\\wow-client\\keybind")

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown


local function OnKeyDown(self, key)
    CallbackRegistry.Trigger(WoWClient_Events.Event.OnKeyDown, key)
    if key == "ESCAPE" then
        CallbackRegistry.Trigger(WoWClient_Events.Event.OnEscapePressed)
    end
end

local function OnKeyUp(self, key)
    CallbackRegistry.Trigger(WoWClient_Events.Event.OnKeyUp, key)
end

---@class KeybindEventsFrame : Frame
---@field awaitingPropagateKeyboardInput boolean set in combat, until keyboard propagation can be turned on

local KeybindEvents = CreateFrame("Frame") --[[@as KeybindEventsFrame]]
KeybindEvents:SetScript("OnKeyDown", OnKeyDown)
KeybindEvents:SetScript("OnKeyUp", OnKeyUp)

if not InCombatLockdown() then
    KeybindEvents:SetPropagateKeyboardInput(true)
else
    KeybindEvents.awaitingPropagateKeyboardInput = true
    KeybindEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
    KeybindEvents:SetScript("OnEvent", function(self, event)
        if not InCombatLockdown() then
            self.awaitingPropagateKeyboardInput = false
            KeybindEvents:SetPropagateKeyboardInput(true)
            KeybindEvents:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end)
end


local function DisableKeyPropagation()
    if InCombatLockdown() then return end
    KeybindEvents:SetPropagateKeyboardInput(false)
end

local function EnableKeyPropagation()
    if InCombatLockdown() then return end
    KeybindEvents:SetPropagateKeyboardInput(true)
end

local KeyPropagationTimer = LazyTimer.New()
KeyPropagationTimer:SetAction(EnableKeyPropagation)

function WoWClient_Keybind.BlockKeyEvent()
    if InCombatLockdown() then return end

    DisableKeyPropagation()
    KeyPropagationTimer:Start(0)
end

local function HandleModifierKey(key, bindingKey)
    if not bindingKey then return false end
    local requiresAlt = bindingKey:find("ALT%-") ~= nil
    local requiresCtrl = bindingKey:find("CTRL%-") ~= nil
    local requiresShift = bindingKey:find("SHIFT%-") ~= nil
    local requiresMeta = bindingKey:find("META%-") ~= nil

    if requiresAlt and not IsAltKeyDown() then return false end
    if requiresCtrl and not IsControlKeyDown() then return false end
    if requiresShift and not IsShiftKeyDown() then return false end
    if requiresMeta and not IsMetaKeyDown() then return false end

    if key == bindingKey then return true end

    local baseKey = bindingKey:gsub("ALT%-", ""):gsub("CTRL%-", ""):gsub("SHIFT%-", ""):gsub("META%-", "")
    return key == baseKey
end

--- Whether `key` (with the modifiers held now) is one of the keys bound to `binding`.
---@param key string
---@param binding string? a binding's name ("TOGGLEGAMEMENU")
---@return boolean
function WoWClient_Keybind.IsKeyBinding(key, binding)
    if not binding then return false end
    local bindingKey1, bindingKey2 = GetBindingKey(binding)
    return HandleModifierKey(key, bindingKey1) or HandleModifierKey(key, bindingKey2)
end

--- Whether `binding` has a key.
---@param binding string
---@return boolean
function WoWClient_Keybind.IsKeyBindingSet(binding)
    local bindingKey1, bindingKey2 = GetBindingKey(binding)
    return (bindingKey1 ~= nil or bindingKey2 ~= nil)
end
