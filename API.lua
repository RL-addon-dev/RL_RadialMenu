--[[
    Public API (global RLRadialMenuAPI) for other addons and macros.

        RLRadialMenuAPI.OpenSettingUI()   toggles the settings window

    RLRadialMenuAPI_OpenSettingUI is the same function, as a plain global for the .toc's
    AddonCompartmentFunc (the minimap addon drawer).
]]

local env = select(2, ...)
RLRadialMenuAPI = RLRadialMenuAPI or {}

do -- @\\Setting
    local Setting = env.AX_Modules:Await("@\\Setting")
    RLRadialMenuAPI_OpenSettingUI = Setting.OpenSettingUI
    RLRadialMenuAPI.OpenSettingUI = Setting.OpenSettingUI
end
