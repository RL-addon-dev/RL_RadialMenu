--[[
    The slash commands: /radial, /radialmenu and /rm open the settings, or close them when open.
    Everything else is done there. /rm perf turns the performance log on or off (Perf.lua).
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

SlashCommand.AddFromSchema({
    { name = COMMAND_NAME, command = COMMAND_SLASHES, callback = OnCommand }
})
