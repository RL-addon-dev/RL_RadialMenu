--[[
    Rings_Common: small helpers the Menus tab's files share (the menu page, its setting rows and
    the Import page).
]]

local env = select(2, ...)
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Rings_Common = env.AX_Modules:New("@\\Setting\\Rings\\Common")

local SettingFrame = _G[Setting_Preload.FRAME_NAME]

-- Each scope's name in locale keys ("Config - Rings - Card - Account"...), built on first use,
-- because Ring_Data loads after the settings.
local scopeKeyNames

--- The name scope `scope` (a Ring_Data.Scope value) has in locale keys: "Account", "Class" or
--- "Character".
---@param scope string
---@return string
function Rings_Common.GetScopeKeyName(scope)
    scopeKeyNames = scopeKeyNames or {
        [Ring_Data.Scope.Account]   = "Account",
        [Ring_Data.Scope.Class]     = "Class",
        [Ring_Data.Scope.Character] = "Character",
    }
    return scopeKeyNames[scope] or scopeKeyNames[Ring_Data.Scope.Account]
end

--- Class `class`'s name ("Mage" for "MAGE"), or the token where the client has no names.
---@param class string
---@return string
function Rings_Common.GetClassName(class)
    return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end

--- Sets up an Available On row's menu with the scopes, widest first (Ring_Data.ScopeOrder).
---@param row table a Setting_Widgets.ElementSelectionMenu
---@return table menu its selection menu button
function Rings_Common.SetupScopeMenu(row)
    local menu = row:GetButtonSelectionMenu()
    menu:SetSelectionMenu(SettingFrame.SelectionMenu)
    local names = {}
    for index, scope in ipairs(Ring_Data.ScopeOrder) do names[index] = Ring_Data.GetScopeName(scope) end
    menu:SetData(names)
    return menu
end
