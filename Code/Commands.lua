--[[
    Slash commands: /radial, /radialmenu and /rm open (toggle) the settings. Everything else is
    done there. /rm perf toggles the performance log (Perf.lua).
]]

local env = select(2, ...)
local SlashCommand = env.AX_Modules:Import("ax_modules\\slash-command")
local Setting = env.AX_Modules:Await("@\\Setting")
local Perf = env.AX_Modules:Import("@\\Perf")

local function OnCommand(message)
    if (message or ""):lower():match("^%s*(%S*)") == "perf" then
        Perf.Toggle()
    else
        Setting.OpenSettingUI()
    end
end

SlashCommand.AddFromSchema({
    { name = "RLRADIALMENU", command = { "radial", "radialmenu", "rm" }, callback = OnCommand }
})
