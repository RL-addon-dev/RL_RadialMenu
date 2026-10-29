--[[
    Loads first, with what every other file uses: addon info, the game version, the addon's events,
    the locale table (filled by Locales\*.lua), and chat output.
]]

local addonName, env = ...

local Path = env.AX_Modules:Import("ax_modules\\path")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")

-- Basic addon information
env.NAME = "RL: |cff00e900Radial Menu|r"
env.NAME_ALT = "Radial Menu" -- without the prefix or color (Edit Mode, About)
env.ICON = Path.Root .. "\\Art\\Icon\\logo-1024.png"
-- From the .toc. The packager sets it from the release tag. A git checkout still has the placeholder.
local tocVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
env.VERSION_STRING = tocVersion:find("^@") and "dev" or tocVersion

-- Which game this is running in (the .toc lists the interfaces it supports). Library menus can be
-- limited to some of them (Code\Menu\Data\Library.lua). WoW Forever's builds are 1.6x (16001...).
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

--- Whether something limited to `versions` exists in the game this is running in. Library
--- menus and action kinds use it.
---@param versions string[]? env.GameVersion values (nil means every version)
---@return boolean
function env.IsForThisGame(versions)
    if not versions then return true end
    for _, version in ipairs(versions) do
        if version == env.GAME_VERSION then return true end
    end
    return false
end

--- Whether WoW Forever's gamepad UI is on (always false on Retail). Its controller features check
--- this, and ConsolePort's check Utils_ConsolePort.IsActive. It changes with
--- "INPUT_DEVICE_INTERFACE_TRANSITION" (Forever only).
---@return boolean
do
    local C_InputInterfaceStyle = _G["C_InputInterfaceStyle"]
    local InterfaceType = Enum and Enum["InputDeviceInterfaceType"]
    function env.IsGamepadUI()
        return C_InputInterfaceStyle ~= nil and InterfaceType ~= nil
            and C_InputInterfaceStyle.GetCurrentStyle() == InterfaceType.Gamepad
    end
end

--- Whether this client has `event`. Registering one it doesn't have is an error, and the game
--- versions don't share every event (WoW Forever lacks some of Retail's).
---@param event string
---@return boolean
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
    DataReady            = "Menu.DataReady",            -- menus loaded and migrated, library menus created (Menu_Data)
    DataChanged          = "Menu.DataChanged",          -- any menu edit, passes a ChangeReason or nil
    LastUsedChanged      = "Menu.LastUsedChanged",      -- a menu's Last Used action changed, passes its menuId
    Rebuilt              = "Menu.Rebuilt",              -- the secure buttons were rebuilt (Menu_Secure)
    DisplayMoved         = "Menu.DisplayMoved",         -- the fixed menu's center may have moved (Menu_Display)
    SearchSourcesChanged = "Menu.SearchSourcesChanged", -- Add Action's search lists are out of date (Menu_Search)
}, "event")

-- Why menus changed or need a rebuild, passed with env.Event.DataChanged. A hand edit passes none.
env.ChangeReason = Utils_Standard.Strict({
    Auto = "auto", -- start-up, library refills or the menu moving, rebuilt without the combat message
}, "change reason")

-- Development only: chat output for menu use (what fired) and drag and drop (cursor info). Set
-- it to true here to turn it on, since there's no in-game switch.
env.DEBUG_MODE = false

-- The locale table, filled by Locales\*.lua.
local L = {}
env.L = L

--- Prints `msg` in chat, after the addon's name.
---@param msg string
function env.Print(msg)
    print(env.NAME .. ": " .. msg)
end

--- Prints `msg` in chat, only with env.DEBUG_MODE (for development).
---@param msg string
function env.Debug(msg)
    if env.DEBUG_MODE then env.Print(msg) end
end
