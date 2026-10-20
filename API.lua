--[[
    The public API, for other addons and macros. It's the global RLRadialMenuAPI.

        RLRadialMenuAPI.OpenSettingUI()   opens the settings window, or closes it when open

    RLRadialMenuAPI_OpenSettingUI is the same function, as a plain global for the .toc's
    AddonCompartmentFunc (the minimap addon drawer). Keep both names: other addons and the .toc
    use them.
]]

local env = select(2, ...)

--- RL Radial Menu's public API.
---@class RLRadialMenuAPI
---@field OpenSettingUI fun() opens the settings window, or closes it when it's open
RLRadialMenuAPI = RLRadialMenuAPI or {}

do
    local Setting = env.AX_Modules:Await("@\\Setting")
    --- Opens the settings window, or closes it when it's open (the .toc's AddonCompartmentFunc).
    RLRadialMenuAPI_OpenSettingUI = Setting.OpenSettingUI
    RLRadialMenuAPI.OpenSettingUI = Setting.OpenSettingUI
end
