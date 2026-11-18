--[[
    Menu_Macros: the account macros that open a menu, one per menu. They're marked by their first
    line, so the macros the addon made are found again and hand-made ones are never touched. A
    macro presses and releases the menu's button at once:

        #rlrm
        /click RLRM_<id> Macro 1
        /click RLRM_<id> Macro

    Menu_Secure decides how a "Macro" click opens the menu. It's a controller's open in WoW
    Forever's gamepad UI or with ConsolePort, and like Relaxed otherwise, so the same macro works
    in both and on any bar. Menu_Crossbar puts it on the crossbar for a controller combo keybind, and the settings'
    Place on Bar puts it on the cursor. The macros are named after their menu, share the icon
    palette, and are deleted with their menu (Reconcile).

        local index = Menu_Macros.Ensure(menu)   -- out of combat

    Every one of them wears the menu badge (Menu_Layout.CreateMenuBadge) in the macro window
    (/macro). Action bar slots and the menus' wheels show it too (Menu_Secure, Menu_Layout).
]]

local env = select(2, ...)
local Menu_Macros = env.AX_Modules:New("@\\Menu\\Macros")
local Menu_Layout = env.AX_Modules:Import("@\\Menu\\Layout")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Await("@\\Menu\\Kinds")

-- The "Macro" click is also read by Menu_Secure's PRE_CLICK snippet.
local MACRO_BODY = "#rlrm\n/click RLRM_%s Macro 1\n/click RLRM_%s Macro"
local MACRO_PATTERN = "^#rlrm\n/click RLRM_(%d+) Macro"
local MACRO_NAME_LENGTH = 16 -- the longest macro name the game takes
-- The same icon in five colours, used in turn.
local MACRO_ICONS = { 4630454, 4630455, 4630456, 4630457, 4630458 }
-- Saved account-wide. Named from when only the crossbar made macros.
local MADE_KEY = "CrossbarMacrosMade"

--- The body of menu `menuId`'s macro.
---@param menuId string|number
---@return string
function Menu_Macros.GetBody(menuId)
    return MACRO_BODY:format(menuId, menuId)
end

--- The menu id a menu macro opens, from its body, or nil for any other macro. Older bodies are
--- rewritten by a migration (Menu_Data's 004_MenuMacroClick.lua).
---@param body string?
---@return string?
function Menu_Macros.Parse(body)
    return body and body:match(MACRO_PATTERN) or nil
end

--- The index of the account macro for menu `menuId`, or nil.
---@param menuId string|number
---@return integer?
function Menu_Macros.Find(menuId)
    for index = 1, GetNumMacros() do
        if Menu_Macros.Parse(GetMacroBody(index)) == tostring(menuId) then return index end
    end
end

--- The menu ids of every menu macro. Renaming or deleting a macro re-sorts the list, so callers
--- look each one up again with Find.
---@return string[]
function Menu_Macros.ListMenuIds()
    local menuIds = {}
    for index = 1, GetNumMacros() do
        local menuId = Menu_Macros.Parse(GetMacroBody(index))
        if menuId then menuIds[#menuIds + 1] = menuId end
    end
    return menuIds
end

--- The menu's name, cut to the macro name limit without splitting a character. "RM" for a menu
--- with no name, since a macro needs one.
---@param menu Menu
---@return string
function Menu_Macros.GetName(menu)
    local name = (menu.name ~= "" and menu.name) or "RM"
    if #name <= MACRO_NAME_LENGTH then return name end
    return (name:sub(1, MACRO_NAME_LENGTH):gsub("[\192-\255][\128-\191]*$", ""))
end

--- Renames macro `index` to menu `menu`'s macro name, when its menu was renamed.
---@param index integer
---@param menu Menu
---@return integer index the macro's index after the rename (renaming re-sorts the list)
function Menu_Macros.Rename(index, menu)
    local name = Menu_Macros.GetName(menu)
    local currentName, icon, body = GetMacroInfo(index)
    if currentName ~= name then return EditMacro(index, name, icon, body) end
    return index
end

--- How many macros were made so far.
---@return integer
local function GetMacrosMade()
    local db = env.Config.DBGlobalPersistent
    return (db and tonumber(db:GetVariable(MADE_KEY))) or 0
end

--- The next macro's icon, the palette colours in turn. The count of macros made so far is saved
--- account-wide (the macros are account macros, and settings resets keep it), so the colours
--- follow the palette's order whatever was deleted since.
---@return number
local function NextIcon()
    return MACRO_ICONS[GetMacrosMade() % #MACRO_ICONS + 1]
end

--- Counts one more macro made (NextIcon).
local function CountMade()
    local db = env.Config.DBGlobalPersistent
    if db then db:SetVariable(MADE_KEY, GetMacrosMade() + 1) end
end

--- The menu's macro, the existing one (renamed if its menu was) or else a new one. Out of combat.
---@param menu Menu
---@return integer? index nil when the account macros are full
function Menu_Macros.Ensure(menu)
    local index = Menu_Macros.Find(menu.id)
    if index then return Menu_Macros.Rename(index, menu) end
    local ok, created = pcall(CreateMacro, Menu_Macros.GetName(menu), NextIcon(), Menu_Macros.GetBody(menu.id), false)
    if not (ok and created) then return nil end
    CountMade()
    return created
end

--- Renames the macros of menus that were renamed, and deletes those whose menu no longer exists
--- (deleting a macro takes it off every bar). Menus that live elsewhere (another class's or
--- character's) keep theirs. Out of combat (Menu_Secure's rebuild).
function Menu_Macros.Reconcile()
    if InCombatLockdown() then return end
    for _, menuId in ipairs(Menu_Macros.ListMenuIds()) do
        local index = Menu_Macros.Find(menuId) -- nil for a duplicate already handled
        local menu = Menu_Data.GetMenu(menuId)
        if index and menu then
            Menu_Macros.Rename(index, menu)
        elseif index and not Menu_Data.GetElsewhereMenu(menuId) then
            DeleteMacro(index)
        end
    end
end



-- The menu badge

local MACRO_WINDOW_ICON_SIZE = 36 -- for a button that isn't laid out yet

--- Whether macro body `body` is one of the addon's menu macros.
---@param body string?
---@return boolean
local function IsMenuBody(body)
    return Menu_Macros.Parse(body) ~= nil
end

--- Whether macro `macro` (an index or a name) is one of the addon's menu macros.
---@param macro integer|string
---@return boolean
function Menu_Macros.IsMenuMacro(macro)
    return IsMenuBody(GetMacroBody(macro))
end

--- Whether `action` is a macro action whose macro is one of the addon's menu macros.
---@param action Action?
---@return boolean
function Menu_Macros.IsMenuAction(action)
    return action ~= nil and action.kind == Menu_Kinds.Kind.Macro and action.name ~= nil
        and Menu_Macros.IsMenuMacro(action.name)
end

---@class MacroWindowButton : Button
---@field Icon Texture?

local windowBadges = {} -- [macro window button] = MenuBadge

--- Shows the badge on a macro window button while it shows menu macro body `body`.
---@param button MacroWindowButton
---@param body string?
local function SetWindowBadge(button, body)
    local isMenu = IsMenuBody(body)
    local badge = windowBadges[button]
    if not badge then
        if not isMenu then return end
        local icon = button.Icon or button
        local size = icon:GetWidth()
        badge = Menu_Layout.CreateMenuBadge(button, icon, size > 0 and size or MACRO_WINDOW_ICON_SIZE)
        windowBadges[button] = badge
    end
    badge:SetShown(isMenu)
end

-- The macro window loads when first opened. The hooks don't change its code.
EventUtil.ContinueOnAddOnLoaded("Blizzard_MacroUI", function()
    local macroFrame = MacroFrame
    if not macroFrame then return end
    hooksecurefunc(macroFrame.MacroSelector, "RunSetup", function(selector, button, selectionIndex)
        local _, _, body = selector:GetSelection(selectionIndex)
        SetWindowBadge(button, body)
    end)
    hooksecurefunc(macroFrame, "SelectMacro", function(frame)
        local index = frame:GetSelectedIndex()
        local body = index and GetMacroBody(frame:GetMacroDataIndex(index))
        SetWindowBadge(frame.SelectedMacroButton, body)
    end)
end)
