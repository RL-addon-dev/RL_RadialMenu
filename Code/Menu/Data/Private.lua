--[[
    Menu data: the helpers its files share, in the Private module. The rest of the addon uses the
    public Menu_Data functions instead.

    Loads first in Data.xml, so it creates both modules. The helpers cover these things.
        - Saved tables: where menus, keybinds and other menu data are stored (Store.lua's header
          lists them).
        - Change notification: Changed, after every menu edit.
        - Keeping menus consistent: NormalizeMenu, and moving remembered scroll positions along
          when actions move.
        - Small shared lookups: the player's class, a menu the user can edit, sorting by name.
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Data = env.AX_Modules:New("@\\Menu\\Data")
local Private = env.AX_Modules:New("@\\Menu\\Data\\Private")

local type, pairs, ipairs, tonumber = type, pairs, ipairs, tonumber

-- Fields menus no longer have. These are per menu settings that became global ones, and
-- `contents` (how a menu was filled, now only library menus fill themselves, by their `library` key).
local REMOVED_MENU_FIELDS = { "revealDelay", "deadzone", "probeSize", "contents" }

-- Why an edit was refused. The settings print it in chat, like "Couldn't add action: menu not found".
Private.EditError = {
    MenuNotFound    = L["Config - Menus - Edit - Error - MenuNotFound"],
    ActionNotFound  = L["Config - Menus - Edit - Error - ActionNotFound"],
    Library         = L["Config - Menus - Edit - Error - Library"],
    NotQuickAction  = L["Config - Menus - Edit - Error - NotQuickAction"],
    UnknownKind     = L["Config - Menus - Edit - Error - UnknownKind"], -- format with the kind
}

-- Saved tables

--- Table `key` in the saved variables of `db` (one of the Config.DB... databases), created when
--- it's missing.
---@param db table
---@param key string
---@return table
function Private.GetStoredTable(db, key)
    return Utils_Standard.GetOrCreateTable(db:GetData(), key)
end

--- The player's class file name ("MAGE"). Class menus and their keybinds are saved under it.
---@return string
function Private.GetPlayerClass()
    return (select(2, UnitClass("player")))
end

--- This class's table inside account-wide table `key`, which holds one table per class.
---@param key string
---@return table
function Private.GetClassStoredTable(key)
    local byClass = Private.GetStoredTable(Config.DBGlobalPersistent, key)
    return Utils_Standard.GetOrCreateTable(byClass, Private.GetPlayerClass())
end

--- The menus saved in `scope`, by id.
---@param scope string a Menu_Data.Scope value
---@return table<string, Menu>
function Private.GetScopeTable(scope)
    if scope == Menu_Data.Scope.Character then
        return Private.GetStoredTable(Config.DBLocalPersistent, "Menus")
    elseif scope == Menu_Data.Scope.Class then
        return Private.GetClassStoredTable("ClassMenus")
    end
    return Private.GetStoredTable(Config.DBGlobalPersistent, "Menus")
end

-- Changes

--- Announces a menu edit with env.Event.DataChanged. The openable menus are forgotten first, so
--- listeners already get the new ones.
---@param reason string? an env.ChangeReason value, nil for an edit by hand
function Private.Changed(reason)
    Private.ForgetOpenableMenus()
    CallbackRegistry.Trigger(env.Event.DataChanged, reason)
end

--- Menu `id` when the user can edit it by hand, which library menus can't be.
---@param id string|number
---@return Menu? menu nil when it can't be edited
---@return string scopeOrError its scope (Menu_Data.Scope), or why it can't be edited (Private.EditError)
function Private.GetEditableMenu(id)
    local menu, scope = Menu_Data.GetMenu(id)
    if not menu then return nil, Private.EditError.MenuNotFound end
    if Menu_Data.IsLibraryMenu(menu) then return nil, Private.EditError.Library end
    return menu, scope
end

--- Fills defaults and drops what a menu may no longer hold. Run after every edit that could leave
--- a menu inconsistent.
---@param menu Menu
function Private.NormalizeMenu(menu)
    for _, key in ipairs(REMOVED_MENU_FIELDS) do
        menu[key] = nil
    end
    if type(menu.actions) ~= "table" then menu.actions = {} end
    -- Submenus used to have an "open" or "scroll" mode. They always scroll now.
    for _, action in ipairs(menu.actions) do
        if action.kind == Menu_Kinds.Kind.Submenu then (action --[[@as SubmenuAction]]).nest = nil end
    end
    -- New menus start without a quick action. Releasing in the center then cancels, so an action
    -- used last (a Hearthstone, a potion) doesn't fire again by accident. Close in the center is
    -- saved as an empty center, because both cancel, and an empty one toggles with Last Used and
    -- has no X.
    if type(menu.quickAction) ~= "table" or menu.quickAction.kind == Menu_Kinds.Kind.Close then
        menu.quickAction = nil
    end
end

-- Remembered scroll positions

--- After actions move, keeps each remembered scroll position (saved by action index) on the same
--- action.
---@param menu Menu
---@param map fun(oldIndex: integer): integer? the new index, or nil when that action is gone
function Private.RemapActionIndices(menu, map)
    local scroll = Private.GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    local prefix = menu.id .. ":"
    local remembered = {}
    for key, value in pairs(scroll) do
        if key:sub(1, #prefix) == prefix then
            remembered[tonumber(key:sub(#prefix + 1))] = value
            scroll[key] = nil
        end
    end
    for index, value in pairs(remembered) do
        local newIndex = map(index)
        if newIndex then scroll[prefix .. newIndex] = value end
    end
end

--- Keeps scroll positions on their actions after an action is inserted at `index`.
---@param menu Menu
---@param index integer
function Private.ShiftAfterInsert(menu, index)
    Private.RemapActionIndices(menu, function(i) return (i >= index and i + 1) or i end)
end

--- Keeps scroll positions on their actions after action `index` is removed (its own is dropped).
---@param menu Menu
---@param index integer
function Private.ShiftAfterRemove(menu, index)
    Private.RemapActionIndices(menu, function(i)
        if i == index then return nil end
        return (i > index and i - 1) or i
    end)
end

-- Sorting

--- A menu's name for sorting, so lists ignore case.
---@param menu Menu
---@return string
function Private.SortName(menu)
    return (menu.name or ""):lower()
end
