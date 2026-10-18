--[[
    Ring_Secure (see Snippets.lua): rebuilding every menu's button and keybind (Setup.lua, Keys.lua)
    after env.Event.DataChanged and settings changes. Rebuilds happen out of combat, and never while
    a menu is held open, because the attributes the release is about to use must match what's shown.
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Crossbar = env.AX_Modules:Import("@\\Ring\\Crossbar")
local Ring_Secure = env.AX_Modules:Import("@\\Ring\\Secure")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")

local InCombatLockdown = InCombatLockdown

-- The settings a rebuild reads. They live in secure attributes, or decide what the snippets and
-- the bindings do.
local REBUILD_SETTINGS = {
    Config.Key.Deadzone,             -- Distance to Select
    Config.Key.ProbeSize,            -- the center probe
    Config.Key.WorldMarkerPlacement, -- world marker actions' macro
    Config.Key.TargetMarkerUnit,     -- target markers' tap copies
    Config.Key.RightClickDismiss,    -- whether held menus bind right click
    Config.Key.MenuStyle,            -- what the release and the mouse do
    Config.Key.FlickToSelect,        -- what the stick's release does
}

local QueueRebuild -- defined below, and also run when the open menu is released (Callbacks.lua)



-- Rebuild: out of combat, with the menu data ready, and not while a menu is held open. Changes
-- made meanwhile are queued and applied as soon as all three hold.

local rebuildQueued = false
local nextFramePending = false -- RequestRebuild's next-frame check is scheduled
local frameRefsSet = false
local combatWaiter = CreateFrame("Frame")

--- Rebuilds every menu's button and keybind. Must be called out of combat.
local function Rebuild()
    rebuildQueued = false
    if not frameRefsSet then
        SecureHandlerSetFrameRef(Private.Controller, "screen", Private.Screen)
        SecureHandlerSetFrameRef(Private.Controller, "probe", Private.Probe)
        SecureHandlerSetFrameRef(Private.Controller, "helper", Private.Helper)
        if Ring_Kinds.ActionBarPageFrame then
            SecureHandlerSetFrameRef(Private.Controller, "actionbarpage", Ring_Kinds.ActionBarPageFrame)
        end
        frameRefsSet = true
    end
    ClearOverrideBindings(Private.Controller)
    ClearOverrideBindings(Private.Helper)

    -- Menus that were deleted, or lost their keybind, keep their button (frames can't be
    -- destroyed) but become inert.
    for ringId, button in pairs(Private.buttonsById) do
        button:SetAttribute(Ring_Secure.Attribute.Count, 0)
        button:SetAttribute(Ring_Secure.Attribute.Quick, nil)
        Private.ringsById[ringId] = nil
    end

    -- Only keybound menus get a button. A menu is opened by its key, and its submenus' actions are
    -- set on its own button (Ring_Live), so submenus need none of their own.
    wipe(Private.pendingBindings)
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if Ring_Data.GetBinding(ring.id) then Private.SetupRing(ring) end
    end
    Private.BindMenuKeys()
    -- Crossbar combo macros are renamed with their menu, and deleted with their combo (Ring_Crossbar).
    Ring_Crossbar.Reconcile()
    CallbackRegistry.Trigger(env.Event.Rebuilt)
end

--- Runs a queued rebuild if it can run now. Otherwise it runs when combat ends (combatWaiter) or
--- the open menu is released (OnRingClose).
QueueRebuild = function()
    if not rebuildQueued or not Ring_Data.IsReady() then return end
    if InCombatLockdown() then
        combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if Private.IsMenuHeld() then return end
    Rebuild()
end

--- Asks for a rebuild next frame, so several changes at once (built-in menus refilled together, a
--- settings reset) cause one.
---@param reason string? env.ChangeReason.Auto for automatic updates (quest items, zone ability),
--- which skip the combat message
local function RequestRebuild(reason)
    if not rebuildQueued and reason ~= env.ChangeReason.Auto and InCombatLockdown() and Ring_Data.IsReady() then
        env.Print(L["Ring - Rebuild - AfterCombat"])
    end
    rebuildQueued = true
    if nextFramePending then return end
    nextFramePending = true
    C_Timer.After(0, function()
        nextFramePending = false
        QueueRebuild()
    end)
end

combatWaiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    QueueRebuild()
end)



-- What asks for a rebuild

CallbackRegistry.Add(env.Event.DataReady, function() RequestRebuild(env.ChangeReason.Auto) end)
CallbackRegistry.Add(env.Event.DataChanged, function(_, reason) RequestRebuild(reason) end)
CallbackRegistry.Add(env.Event.ConfigReset, function() RequestRebuild() end)
-- Open At, Select From = Menu Center, and the fixed menu's center live in secure attributes too.
CallbackRegistry.Add(env.Event.DisplayMoved, function() RequestRebuild(env.ChangeReason.Auto) end)
for _, key in ipairs(REBUILD_SETTINGS) do
    Config.OnChange(key, function() RequestRebuild() end)
end
-- Switching between WoW Forever's gamepad and keyboard and mouse UI changes world markers'
-- placement. The event doesn't exist on Retail.
do
    local styleWatcher = CreateFrame("Frame")
    if pcall(styleWatcher.RegisterEvent, styleWatcher, "INPUT_DEVICE_INTERFACE_TRANSITION") then
        styleWatcher:SetScript("OnEvent", function() RequestRebuild(env.ChangeReason.Auto) end)
    end
end

Private.QueueRebuild = QueueRebuild
