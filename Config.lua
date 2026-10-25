--[[
    Saved variables. This file names them, sets their defaults and loads them when the addon loads
    (then fires env.Event.DatabaseReady). It also defines the settings' keys and accessors
    (Config.Key, Config.Get, Config.Set, Config.OnChange), and how the settings UI (AX_Settings)
    reads and writes them.

    Loads after Preload.lua (enums) and before libs\AX_Settings\AX_Settings.xml, which
    reads env.AX_SettingsOptions while it loads.

        RL_RadialMenuDB_Global              settings (General tab), wiped by the settings' Reset
        RL_RadialMenuDB_Global_Persistent   account data kept by Reset: menus, keybinds, positions
        RL_RadialMenuDB_Local               per character settings (none yet)
        RL_RadialMenuDB_Local_Persistent    per character data: menus, keybinds, Last Used...
    The menus' own data is described in Code\Ring\Data\Store.lua.
]]

local env = select(2, ...)

local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local SavedVariables = env.AX_Modules:Import("ax_modules\\saved-variables")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")

local Config = {}
env.Config = Config



-- Values of settings with a fixed set of choices. They're the positions of the options in the
-- settings' dropdowns (Setting_Schema.lua), so the two must list them in the same order.
local Enum = {}
env.Enum = Enum

-- Open Menus At (DisplayOpenAt): at the cursor, or at the fixed position set in Edit Mode.
Enum.OpenAt = {
    Cursor = 1,
    Fixed  = 2
}

-- Select From (SelectFrom), fixed position only: the direction moved from the key down spot, or
-- where the cursor is relative to the menu's center.
Enum.SelectFrom = {
    Cursor = 1,
    Menu   = 2
}

-- Menu Style (MenuStyle), named like the ping wheel's. Quick picks on the keybind's release.
-- Relaxed keeps the menu open after the release, and a left click picks (Ring_Secure).
Enum.MenuStyle = {
    Quick   = 1,
    Relaxed = 2
}

-- Place World Markers (WorldMarkerPlacement): on the ground under the mouse, or with the game's
-- targeting circle (click the ground).
Enum.WorldMarkerPlacement = {
    Mouse = 1,
    Click = 2
}

-- Mark Target Markers On (TargetMarkerUnit): your target, or the unit under the mouse when the
-- keybind was pressed (out of combat, Ring_Secure). CursorFocus also marks any unit, in combat
-- too, in menus of only target markers, by stealing your focus while the menu is open.
Enum.TargetMarkerUnit = {
    Target = 1,
    Cursor = 2,
    CursorFocus = 3
}



-- Defaults

local NAME_GLOBAL = "RL_RadialMenuDB_Global"
local NAME_GLOBAL_PERSISTENT = "RL_RadialMenuDB_Global_Persistent"
local NAME_LOCAL = "RL_RadialMenuDB_Local"
local NAME_LOCAL_PERSISTENT = "RL_RadialMenuDB_Local_Persistent"

local DB_GLOBAL_DEFAULTS = {
    DisplayOpenAt        = Enum.OpenAt.Cursor,
    DisplayScale         = 100,                             -- percent
    ShowActionNames      = true,                            -- the highlighted action's name in the in-game menu
    ShowActionTooltips   = false,                           -- its tooltip, at the HUD Tooltip position
    SelectFrom           = Enum.SelectFrom.Menu,            -- with a fixed position, where angles are measured from
    CursorGuide          = false,                           -- with a fixed position, the gesture's outline
                                                            -- drawn at the cursor
    CursorGuideColor     = { r = 1, g = 1, b = 1 },
    MenuStyle            = Enum.MenuStyle.Quick,
    FlickToSelect        = false,                           -- with a controller, letting go of the aimed right
                                                            -- stick uses the action (Ring_Secure)
    RevealDelay          = 0.15,                            -- seconds
    Deadzone             = 24,                              -- px
    ProbeSize            = 12,                              -- px from the key-down spot (the square is twice this wide)
    RightClickDismiss    = true,                            -- right click closes a held menu (Ring_Secure)
    WorldMarkerPlacement = Enum.WorldMarkerPlacement.Mouse,
    TargetMarkerUnit     = Enum.TargetMarkerUnit.Cursor,    -- like the ping menu
    PreviewHideHidden    = false,                           -- the settings preview leaves out actions hidden
                                                            -- in game right now (the eye toggle)
}

-- Distance to Select's slider limits, in px (Setting_Schema). Ring_View also reads the largest.
Config.DEADZONE_MIN = 8
Config.DEADZONE_MAX = 60

-- The keys settings are saved under in the global database, one per default above. Pass them to
-- Config.Get / Set / OnChange (below) and the schema's `key`: Config.Get(Config.Key.MenuStyle).
local Key = {}
for name in pairs(DB_GLOBAL_DEFAULTS) do Key[name] = name end
Config.Key = Utils_Standard.Strict(Key, "setting key")

local DB_GLOBAL_PERSISTENT_DEFAULTS = {}
local DB_LOCAL_DEFAULTS = {}
local DB_LOCAL_PERSISTENT_DEFAULTS = {} -- menus' own data (Code\Ring\Data\Store.lua)

Config.DBGlobal = nil
Config.DBGlobalPersistent = nil
Config.DBLocal = nil
Config.DBLocalPersistent = nil

--- Loads the saved variables with their defaults, then fires env.Event.DatabaseReady.
function Config.LoadDB()
    Config.DBGlobal = SavedVariables.RegisterDatabase(NAME_GLOBAL).defaults(DB_GLOBAL_DEFAULTS)
    Config.DBGlobalPersistent = SavedVariables.RegisterDatabase(NAME_GLOBAL_PERSISTENT).defaults(DB_GLOBAL_PERSISTENT_DEFAULTS)
    Config.DBLocal = SavedVariables.RegisterDatabase(NAME_LOCAL).defaults(DB_LOCAL_DEFAULTS)
    Config.DBLocalPersistent = SavedVariables.RegisterDatabase(NAME_LOCAL_PERSISTENT).defaults(DB_LOCAL_PERSISTENT_DEFAULTS)

    CallbackRegistry.Trigger(env.Event.DatabaseReady)
end

--- A setting's value, or its default. Only after env.Event.DatabaseReady.
---@param key string a Config.Key value
---@return any
function Config.Get(key)
    return Config.DBGlobal:GetVariable(key)
end

--- Saves a setting. If the value changed, its Config.OnChange callbacks run.
---@param key string a Config.Key value
---@param value any
function Config.Set(key, value)
    Config.DBGlobal:SetVariable(key, value)
end

--- Calls `callback(event, value)` whenever a setting is changed (by Config.Set or the settings).
--- Can be registered at load time. A settings reset doesn't call it, so listen to
--- env.Event.ConfigReset as well when that matters.
---@param key string a Config.Key value
---@param callback fun(event: string, value: any)
function Config.OnChange(key, callback)
    SavedVariables.OnChange(NAME_GLOBAL, key, callback)
end

-- Saved variables exist once the addon has loaded.
CallbackRegistry.Add("WoWClient.OnAddonLoaded", Config.LoadDB)



-- AX_Settings (libs\AX_Settings): read when AX_Settings.xml loads, after this file.
env.AX_SettingsOptions = {
    prefix  = "RLRM",
    title   = env.NAME,
    storage = {
        get = Config.Get,
        set = Config.Set,
    },
    windowPosition = {
        get = function()
            local stored = Config.DBGlobalPersistent and Config.DBGlobalPersistent:GetData()
            return stored and stored.SettingWindowPosition
        end,
        set = function(position)
            Config.DBGlobalPersistent:GetData().SettingWindowPosition = position
        end,
    },
    getSchema = function() return env.AX_Modules:Import("@\\Setting\\Schema").SCHEMA end,
    -- Not in Options, AddOns when the game loads in WoW Forever's gamepad UI, since the settings
    -- open from the addon drawer there (switching later leaves it as it was).
    showInOptions = function() return not env.IsGamepadUI() end,
}
