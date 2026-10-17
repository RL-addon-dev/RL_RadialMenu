--[[
    Loads first, with what every other file uses. Addon info, the game version, the addon's events,
    the locale table (filled by Locales\*.lua), and chat output.
]]

local addonName, env = ...

local Path = env.AX_Modules:Import("ax_modules\\path")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")

-- Basic addon information
env.NAME = "RL: |cff00e900Radial Menu|r"
env.NAME_ALT = "Radial Menu" -- without the prefix / color (Edit Mode, About)
env.ICON = Path.Root .. "\\Art\\Icon\\logo-1024.png"
env.VERSION_STRING = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?" -- from the .toc

-- Which game this is running in (the .toc lists the interfaces it supports). Built-in menus can be
-- limited to some of them (Code\Ring\Data\BuiltIn.lua). WoW Forever's builds are 1.6x (16001...).
env.GameVersion = Utils_Standard.Strict({
    Retail  = "retail",
    Forever = "forever",
    Classic = "classic", -- any other classic client
}, "game version")
do
    local interface = select(4, GetBuildInfo())
    env.GAME_VERSION = (interface >= 110000 and env.GameVersion.Retail)
        or (interface >= 16000 and interface < 20000 and env.GameVersion.Forever)
        or env.GameVersion.Classic
end

--- Whether something limited to `versions` (a list of env.GameVersion values; nil = every
--- version) exists in the game this is running in. Built-in menus and action kinds use it.
function env.IsForThisGame(versions)
    if not versions then return true end
    for _, version in ipairs(versions) do
        if version == env.GAME_VERSION then return true end
    end
    return false
end

--- Whether WoW Forever's gamepad UI is on (always false on retail). Every controller feature
--- checks this: controller support only exists in that UI. It changes with
--- "INPUT_DEVICE_INTERFACE_TRANSITION" (Forever only).
do
    local C_InputInterfaceStyle = _G["C_InputInterfaceStyle"]
    local InterfaceType = Enum and Enum["InputDeviceInterfaceType"]
    function env.IsGamepadUI()
        return C_InputInterfaceStyle ~= nil and InterfaceType ~= nil
            and C_InputInterfaceStyle.GetCurrentStyle() == InterfaceType.Gamepad
    end
end

--- Whether this client has `event`: registering one it doesn't have is an error, and the game
--- versions don't share every event (WoW Forever lacks some of retail's).
function env.IsEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then return C_EventUtils.IsEventValid(event) end
    return true
end

-- The addon's own CallbackRegistry events. Comments show what each passes to its callbacks.
-- Not here are the settings window's events (Setting_Enum.Event, from AX_Settings) and a single
-- setting changing (Config.OnChange).
env.Event = Utils_Standard.Strict({
    DatabaseReady        = "Preload.DatabaseReady",     -- saved variables loaded (Config.lua)
    ConfigReset          = "Config.Reset",              -- settings reset to defaults, without any OnChange callbacks
    DataReady            = "Ring.DataReady",            -- menus loaded and migrated, built-ins created (Ring_Data)
    DataChanged          = "Ring.DataChanged",          -- any menu edit, passes a ChangeReason or nil
    LastUsedChanged      = "Ring.LastUsedChanged",      -- a menu's Last Used action changed, passes its ringId
    Rebuilt              = "Ring.Rebuilt",              -- the secure buttons were rebuilt (Ring_Secure)
    DisplayMoved         = "Ring.DisplayMoved",         -- the fixed menu's center may have moved (Ring_Display)
    SearchSourcesChanged = "Ring.SearchSourcesChanged", -- Add Action's search lists are out of date (Ring_Search)
}, "event")

-- Why menus changed or need a rebuild, passed with env.Event.DataChanged. A hand edit passes none.
env.ChangeReason = Utils_Standard.Strict({
    Auto = "auto", -- start-up, built-in refills or the menu moving, rebuilt without the combat message
}, "change reason")

-- Development only: chat output for menu use (what fired) and drag & drop (cursor info). Set to
-- true here to turn it on; there's no in-game switch.
env.DEBUG_MODE = false

-- Localization table
local L = {}; env.L = L

-- Chat output
function env.Print(msg)
    print(env.NAME .. ": " .. msg)
end

--- Chat output for development, only with env.DEBUG_MODE.
function env.Debug(msg)
    if env.DEBUG_MODE then env.Print(msg) end
end
