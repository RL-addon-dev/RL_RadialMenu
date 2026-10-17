--[[
    Slash commands: /radial, /radialmenu and /rm open (toggle) the settings. Everything else is
    done there. /rm perf toggles the performance log (Perf.lua).

    Removed while WoW Forever's gamepad UI is on, and added back when it's off. In that UI, 
    any addon slash command crashes the game (a Blizzard bug).
    the settings are still in the addon drawer.
]]

local env = select(2, ...)
local SlashCommand = env.AX_Modules:Import("ax_modules\\slash-command")
local Setting = env.AX_Modules:Await("@\\Setting")
local Perf = env.AX_Modules:Import("@\\Perf")

local COMMAND_NAME = "RLRADIALMENU"

local function OnCommand(message)
    if (message or ""):lower():match("^%s*(%S*)") == "perf" then
        Perf.Toggle()
    else
        Setting.OpenSettingUI()
    end
end

local registered = false

local function UpdateCommands()
    local wanted = not env.IsGamepadUI()
    if wanted == registered then return end
    registered = wanted
    if wanted then
        SlashCommand.AddFromSchema({
            { name = COMMAND_NAME, command = { "radial", "radialmenu", "rm" }, callback = OnCommand }
        })
    else
        SlashCommand.RemoveSlashCommand(COMMAND_NAME)
    end
end

UpdateCommands()

-- The interface style may only be known by login, and changes when the player switches modes.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
pcall(watcher.RegisterEvent, watcher, "INPUT_DEVICE_INTERFACE_TRANSITION")
watcher:SetScript("OnEvent", UpdateCommands)
