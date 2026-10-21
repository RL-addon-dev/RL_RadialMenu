--[[
    Menus_Common: small helpers the Menus tab's files share (the menu page, its setting rows and
    the Import page).
]]

local env = select(2, ...)
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Menus_Common = env.AX_Modules:New("@\\Setting\\Menus\\Common")

local SettingFrame = _G[Setting_Preload.FRAME_NAME]

-- Each scope's name in locale keys ("Config - Menus - Card - Account"...), built on first use,
-- because Menu_Data loads after the settings.
local scopeKeyNames

--- The name scope `scope` (a Menu_Data.Scope value) has in locale keys: "Account", "Class" or
--- "Character".
---@param scope string
---@return string
function Menus_Common.GetScopeKeyName(scope)
    scopeKeyNames = scopeKeyNames or {
        [Menu_Data.Scope.Account]   = "Account",
        [Menu_Data.Scope.Class]     = "Class",
        [Menu_Data.Scope.Character] = "Character",
    }
    return scopeKeyNames[scope] or scopeKeyNames[Menu_Data.Scope.Account]
end

--- Class `class`'s name ("Mage" for "MAGE"), or the token where the client has no names.
---@param class string
---@return string
function Menus_Common.GetClassName(class)
    return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end

--- Sets up an Available On row's menu with the scopes, widest first (Menu_Data.ScopeOrder).
---@param row table a Setting_Widgets.ElementSelectionMenu
---@return table menu its selection menu button
function Menus_Common.SetupScopeMenu(row)
    local menu = row:GetButtonSelectionMenu()
    menu:SetSelectionMenu(SettingFrame.SelectionMenu)
    local names = {}
    for index, scope in ipairs(Menu_Data.ScopeOrder) do names[index] = Menu_Data.GetScopeName(scope) end
    menu:SetData(names)
    return menu
end
