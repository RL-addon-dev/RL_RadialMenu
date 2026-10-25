--[[
    The slash commands: /radial, /radialmenu and /rm open the settings, or close them when open.
    Everything else is done there. /rm perf turns the performance log on or off (Perf.lua).

    They're removed while WoW Forever's gamepad UI is on, and added back when it's off, because
    in that UI any addon slash command crashes the game (a Blizzard bug). The settings are still
    in the addon drawer there.
]]

local env = select(2, ...)
local SlashCommand = env.AX_Modules:Import("ax_modules\\slash-command")
local Setting = env.AX_Modules:Await("@\\Setting")
local Perf = env.AX_Modules:Import("@\\Perf")

local COMMAND_NAME = "RLRADIALMENU"
local COMMAND_SLASHES = { "radial", "radialmenu", "rm" }
local PERF_ARGUMENT = "perf" -- /rm perf

--- Runs a slash command, with what was typed after it.
---@param message string?
local function OnCommand(message)
    if (message or ""):lower():match("^%s*(%S*)") == PERF_ARGUMENT then
        Perf.Toggle()
    else
        Setting.OpenSettingUI()
    end
end

local registered = false

--- Adds the slash commands, or removes them in WoW Forever's gamepad UI.
local function UpdateCommands()
    local wanted = not env.IsGamepadUI()
    if wanted == registered then return end
    registered = wanted
    if wanted then
        SlashCommand.AddFromSchema({
            { name = COMMAND_NAME, command = COMMAND_SLASHES, callback = OnCommand }
        })
    else
        SlashCommand.RemoveSlashCommand(COMMAND_NAME)
    end
end

UpdateCommands()

-- The interface style may only be known at login, and it changes when the player switches modes.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
pcall(watcher.RegisterEvent, watcher, "INPUT_DEVICE_INTERFACE_TRANSITION")
watcher:SetScript("OnEvent", UpdateCommands)
