--[[
    AX_Settings options: everything the framework needs from the addon that embeds it.

    The addon sets env.AX_SettingsOptions before AX_Settings.xml loads (the framework
    creates its frames while loading):

        env.AX_SettingsOptions = {
            prefix         = "MYADDON",          -- global frame names: <prefix>_SettingFrame, _SettingWindow
            title          = "My Addon",         -- window title and Options -> AddOns category
            storage        = {                   -- where widget values (schema `key`s) live
                get = function(key) end,
                set = function(key, value) end,
            },
            windowPosition = {                   -- optional: remember where the window was dragged
                get = function() end,            --   -> { point, relativePoint, x, y } or nil
                set = function(position) end,
            },
            getSchema      = function() end,     -- the schema (called when the UI is first built)
        }
]]

local env = select(2, ...)
local Setting_Options = env.AX_Modules:New("@\\Setting\\Options")

local options = env.AX_SettingsOptions
assert(type(options) == "table", "AX_Settings: set env.AX_SettingsOptions before AX_Settings.xml loads")
assert(type(options.prefix) == "string", "AX_Settings: options.prefix is required")
assert(type(options.storage) == "table" and options.storage.get and options.storage.set, "AX_Settings: options.storage needs get and set")
assert(type(options.getSchema) == "function", "AX_Settings: options.getSchema is required")

-- This library's own folder (AX_Settings), for its art: worked out from this file's own path
-- (…\<library>\Setting\Setting_Options.lua). Falls back to the usual place,
-- <addon>\libs\AX_Settings, if the path can't be read.
do
    local source = debugstack and debugstack(1, 1, 0) or ""
    local folder = source:match("(Interface[/\\][Aa][Dd][Dd][Oo][Nn][Ss][/\\][^%.\"]-)[/\\]Setting[/\\]Setting_Options%.lua")
    Setting_Options.Path = folder and (folder:gsub("/", "\\")) or ("Interface\\AddOns\\" .. select(1, ...) .. "\\libs\\AX_Settings")
end

Setting_Options.prefix = options.prefix
Setting_Options.title = options.title or options.prefix
Setting_Options.storage = options.storage
Setting_Options.windowPosition = options.windowPosition
Setting_Options.getSchema = options.getSchema
