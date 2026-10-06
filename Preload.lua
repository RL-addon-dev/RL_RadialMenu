--[[
    Loads first: what every other file uses. Addon info, the locale table (filled by
    Locales\*.lua), and chat output.
]]

local addonName, env = ...

local Path = env.AX_Modules:Import("ax_modules\\path")

-- Basic addon information
env.NAME = "RL: |cff00e900Radial Menu|r"
env.NAME_ALT = "Radial Menu" -- without the prefix / color (Edit Mode, About)
env.ICON = Path.Root .. "\\Art\\Icon\\logo-1024.png"
env.VERSION_STRING = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?" -- from the .toc

-- Which game this is running in (the .toc lists the interfaces it supports). Built-in menus can be
-- limited to some of them (Code\Ring\Data\BuiltIn.lua). WoW Forever's builds are 1.6x (16001...).
env.GameVersion = setmetatable({
    Retail  = "retail",
    Forever = "forever",
    Classic = "classic", -- any other classic client
}, {
    -- A misspelled name (env.GameVersion.Retial) is an error, not a silent nil.
    __index = function(_, name) error("unknown game version: " .. tostring(name), 2) end,
})
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

--- Whether this client has `event`: registering one it doesn't have is an error, and the game
--- versions don't share every event (WoW Forever lacks some of retail's).
function env.IsEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then return C_EventUtils.IsEventValid(event) end
    return true
end

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
