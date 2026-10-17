--[[
    Ring_Secure (see Snippets.lua): rebuilding every menu's button and keybind (Setup.lua, Keys.lua)
    after env.Event.DataChanged and settings changes. Rebuilds happen out of combat, and never while a
    menu is held open: the attributes the release is about to use must match what's shown.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Crossbar = env.AX_Modules:Import("@\\Ring\\Crossbar")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")

local InCombatLockdown = InCombatLockdown
local Controller, Screen, Probe, Helper = Private.Controller, Private.Screen, Private.Probe, Private.Helper
local ringsById, buttonsById = Private.ringsById, Private.buttonsById
local pendingBindings = Private.pendingBindings
local SetupRing = Private.SetupRing

local QueueRebuild -- defined below; also run when the open menu is released (Callbacks.lua)

-- Rebuild: out of combat, with the menu data ready, and not while a menu is held open. Changes
-- made meanwhile are queued and applied as soon as all three hold.

local rebuildQueued = false
local nextFramePending = false -- RequestRebuild's next-frame check is scheduled
local frameRefsSet = false
local combatWaiter = CreateFrame("Frame")

--- Must be called out of combat.
local function Rebuild()
    rebuildQueued = false
    if not frameRefsSet then
        SecureHandlerSetFrameRef(Controller, "screen", Screen)
        SecureHandlerSetFrameRef(Controller, "probe", Probe)
        SecureHandlerSetFrameRef(Controller, "helper", Helper)
        if Ring_Kinds.ActionBarPageFrame then
            SecureHandlerSetFrameRef(Controller, "actionbarpage", Ring_Kinds.ActionBarPageFrame)
        end
        frameRefsSet = true
    end
    ClearOverrideBindings(Controller)
    ClearOverrideBindings(Helper)

    -- Rings that were deleted, or lost their keybind, keep their button (frames can't be
    -- destroyed) but become inert.
    for ringId, button in pairs(buttonsById) do
        button:SetAttribute("ring-count", 0)
        button:SetAttribute("ring-quick", nil)
        ringsById[ringId] = nil
    end

    -- Only keybound rings get a button: a ring is opened by its key, and its submenus' actions are
    -- set on its own button (Ring_Live), so submenus need none of their own.
    wipe(pendingBindings)
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if Ring_Data.GetBinding(ring.id) then SetupRing(ring) end
    end
    Private.BindMenuKeys()
    -- Crossbar combo macros: renamed with their menu, deleted with their combo (Ring_Crossbar).
    Ring_Crossbar.Reconcile()
    CallbackRegistry.Trigger(env.Event.Rebuilt)
end

--- Runs a queued rebuild if it can run now; otherwise it runs when combat ends (combatWaiter) or
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
local function RequestRebuild(_, reason)
    if not rebuildQueued and reason ~= env.ChangeReason.Auto and InCombatLockdown() and Ring_Data.IsReady() then
        env.Print("menu changes will apply after combat")
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

CallbackRegistry.Add(env.Event.DataReady, function() RequestRebuild(nil, env.ChangeReason.Auto) end)
CallbackRegistry.Add(env.Event.DataChanged, RequestRebuild)
-- Dead zone and center nudge live in secure attributes; reveal delay is read by the view on open.
Config.OnChange(Config.Key.Deadzone, RequestRebuild)
Config.OnChange(Config.Key.ProbeSize, RequestRebuild)
-- World marker actions' macro depends on Place World Markers.
Config.OnChange(Config.Key.WorldMarkerPlacement, RequestRebuild)
-- Target markers' tap copies depend on Mark Target Markers On.
Config.OnChange(Config.Key.TargetMarkerUnit, RequestRebuild)
-- Right-Click to Cancel decides whether held menus bind right click.
Config.OnChange(Config.Key.RightClickDismiss, RequestRebuild)
-- Menu Style decides what the release and the mouse do.
Config.OnChange(Config.Key.MenuStyle, RequestRebuild)
-- Switching between WoW Forever's gamepad and keyboard and mouse UI: world markers' placement.
do
    local styleWatcher = CreateFrame("Frame")
    if pcall(styleWatcher.RegisterEvent, styleWatcher, "INPUT_DEVICE_INTERFACE_TRANSITION") then
        styleWatcher:SetScript("OnEvent", function() RequestRebuild(nil, env.ChangeReason.Auto) end)
    end
end
-- Flick to Select decides what the stick's release does.
Config.OnChange(Config.Key.FlickToSelect, RequestRebuild)
CallbackRegistry.Add(env.Event.ConfigReset, RequestRebuild)
-- Open At, Select From = Menu Center, and the fixed menu's center live in secure attributes too.
CallbackRegistry.Add(env.Event.DisplayMoved, function() RequestRebuild(nil, env.ChangeReason.Auto) end)

Private.QueueRebuild = QueueRebuild
