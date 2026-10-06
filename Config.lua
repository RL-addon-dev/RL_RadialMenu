--[[
    Saved variables: their names and defaults, loading them when the addon loads (then
    "Preload.DatabaseReady"), and how the settings UI (AX_Settings) reads and writes them.

    Loads after Preload.lua (enums) and before libs\AX_Settings\AX_Settings.xml, which
    reads env.AX_SettingsOptions while it loads.

        RL_RadialMenuDB_Global              settings (General tab); wiped by the settings' Reset
        RL_RadialMenuDB_Global_Persistent   account data kept by Reset: menus, keybinds, positions
        RL_RadialMenuDB_Local               per character settings (none yet)
        RL_RadialMenuDB_Local_Persistent    per character data: menus, keybinds, Last Used, ...
    The menus' own data is described in Code\Ring\Data\Store.lua.
]]

local env = select(2, ...)

local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local SavedVariables = env.AX_Modules:Import("ax_modules\\saved-variables")

local Config = {}; env.Config = Config



-- Values of settings with a fixed set of choices. They're the positions of the options in the
-- settings' dropdowns (Setting_Schema.lua), so the two must list them in the same order.
local Enum = {}; env.Enum = Enum

-- Open Menus At (DisplayOpenAt): at the cursor, or at the fixed position set in Edit Mode.
Enum.OpenAt = {
    Cursor = 1,
    Fixed  = 2
}

-- Select From (SelectFrom), fixed position only: the direction moved from the key-down spot, or
-- where the cursor is relative to the menu's center.
Enum.SelectFrom = {
    Cursor = 1,
    Menu   = 2
}

-- Place World Markers (WorldMarkerPlacement): on the ground under the mouse, or with the game's
-- targeting circle (click the ground).
Enum.WorldMarkerPlacement = {
    Mouse = 1,
    Click = 2
}



-- Defaults

local NAME_GLOBAL = "RL_RadialMenuDB_Global"
local NAME_GLOBAL_PERSISTENT = "RL_RadialMenuDB_Global_Persistent"
local NAME_LOCAL = "RL_RadialMenuDB_Local"
local NAME_LOCAL_PERSISTENT = "RL_RadialMenuDB_Local_Persistent"

local DB_GLOBAL_DEFAULTS = {
    DisplayOpenAt = Enum.OpenAt.Cursor,
    DisplayScale  = 100, -- percent
    ShowActionNames = true, -- the highlighted action's name in the in-game menu
    ShowActionTooltips = false, -- its tooltip, at the HUD Tooltip position
    SelectFrom    = Enum.SelectFrom.Cursor, -- fixed position: where angles are measured from
    CursorGuide   = false, -- fixed position: outline of the gesture at the cursor
    CursorGuideColor = { r = 1, g = 1, b = 1 },
    RevealDelay   = 0.15, -- seconds
    Deadzone      = 24,   -- px
    ProbeSize     = 12,   -- px from the key-down spot (the square is twice this wide)
    WorldMarkerPlacement = Enum.WorldMarkerPlacement.Mouse,
}
local DB_GLOBAL_PERSISTENT_DEFAULTS = {}
local DB_LOCAL_DEFAULTS = {}
local DB_LOCAL_PERSISTENT_DEFAULTS = {} -- menus' own data (Code\Ring\Data\Store.lua)

Config.DBGlobal = nil
Config.DBGlobalPersistent = nil
Config.DBLocal = nil
Config.DBLocalPersistent = nil

function Config.LoadDB()
    Config.DBGlobal = SavedVariables.RegisterDatabase(NAME_GLOBAL).defaults(DB_GLOBAL_DEFAULTS)
    Config.DBGlobalPersistent = SavedVariables.RegisterDatabase(NAME_GLOBAL_PERSISTENT).defaults(DB_GLOBAL_PERSISTENT_DEFAULTS)
    Config.DBLocal = SavedVariables.RegisterDatabase(NAME_LOCAL).defaults(DB_LOCAL_DEFAULTS)
    Config.DBLocalPersistent = SavedVariables.RegisterDatabase(NAME_LOCAL_PERSISTENT).defaults(DB_LOCAL_PERSISTENT_DEFAULTS)

    CallbackRegistry.Trigger("Preload.DatabaseReady")
end

-- Saved variables exist once the addon has loaded.
CallbackRegistry.Add("WoWClient.OnAddonLoaded", Config.LoadDB)



-- AX_Settings (libs\AX_Settings): read when AX_Settings.xml loads, after this file.
env.AX_SettingsOptions = {
    prefix  = "RLRM",
    title   = env.NAME,
    storage = {
        get = function(key) return Config.DBGlobal:GetVariable(key) end,
        set = function(key, value) Config.DBGlobal:SetVariable(key, value) end,
    },
    windowPosition = {
        get = function()
            local stored = Config.DBGlobalPersistent and _G[Config.DBGlobalPersistent.databaseName]
            return stored and stored.SettingWindowPosition
        end,
        set = function(position)
            _G[Config.DBGlobalPersistent.databaseName].SettingWindowPosition = position
        end,
    },
    getSchema = function() return env.AX_Modules:Import("@\\Setting\\Schema").SCHEMA end,
}
