--[[
    Slash commands: /radial, /radialmenu and /rm open (toggle) the settings. Everything else is
    done there.
]]

local env = select(2, ...)
local SlashCommand = env.AX_Modules:Import("ax_modules\\slash-command")
local Setting = env.AX_Modules:Await("@\\Setting")

SlashCommand.AddFromSchema({
    { name = "RLRADIALMENU", command = { "radial", "radialmenu", "rm" }, callback = function() Setting.OpenSettingUI() end }
})
