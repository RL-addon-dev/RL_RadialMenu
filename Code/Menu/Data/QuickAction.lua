--[[
    Menu data: the quick action (what a tap fires) and Last Used.

    A menu's center holds its quick action (menu.quickAction), or nothing. That action fires on a
    tap and isn't on the wheel. A wedge dragged onto the center is copied there (the wedge stays),
    and the center's action can be dragged out onto the wheel. A Last Used center is a Last Used
    action (Kinds\LastUsed.lua). What each menu fired last is remembered here, on this character.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

--- The identity (Menu_Data.GetActionKey) of the action last fired from menu `id` on this character,
--- like "item:6948". It's saved by identity, not position, so it survives hidden actions and
--- spread submenus shifting the positions in game.
---@param id string|number
---@return string?
function Menu_Data.GetLastUsedKey(id)
    return Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedAction")[tostring(id)]
end

--- Remembers `key` (Menu_Data.GetActionKey) as the action last fired from menu `id` on this
--- character. This isn't a menu edit, so it fires env.Event.LastUsedChanged instead of
--- env.Event.DataChanged.
---@param id string|number
---@param key string
function Menu_Data.SetLastUsedKey(id, key)
    Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedAction")[tostring(id)] = key
    CallbackRegistry.Trigger(env.Event.LastUsedChanged, tostring(id))
end

--- The action a tap fires (in the center), or nil.
---@param menu Menu
---@return Action?
function Menu_Data.GetQuickAction(menu)
    return menu.quickAction
end

--- Empties the center, so the menu has no quick action.
---@param id string|number
---@return boolean ok
function Menu_Data.ClearQuickAction(id)
    local menu = Menu_Data.GetMenu(id)
    if not menu then return false end
    menu.quickAction = nil
    Private.Changed()
    return true
end

--- Puts `action`, or nothing, in the center. NormalizeMenu keeps Close there as an empty center.
---@param menu Menu
---@param action Action?
local function SetCenter(menu, action)
    menu.quickAction = action
    Private.NormalizeMenu(menu)
end

--- Puts `action` in the center as the menu's quick action, fired by a tap and not shown on the
--- wheel.
---@param id string|number
---@param action Action
---@return boolean ok
---@return string? error why not, for the chat message
function Menu_Data.SetQuickAction(id, action)
    local menu = Menu_Data.GetMenu(id)
    if not menu then return false, Private.EditError.MenuNotFound end
    if not Menu_Data.CanBeQuickAction(action) then return false, Private.EditError.NotQuickAction end
    local ok, err = Menu_Data.ValidateAction(menu.id, action)
    if not ok then return false, err end
    SetCenter(menu, action)
    Private.Changed()
    return true
end

--- Copies action `index` into the center, replacing what was there. The action stays on the wheel.
---@param id string|number
---@param index integer
---@return boolean ok
---@return string? error why not, for the chat message
function Menu_Data.CopyActionToQuick(id, index)
    local menu = Menu_Data.GetMenu(id)
    local action = menu and menu.actions[index]
    if not action then return false, Private.EditError.ActionNotFound end
    if not Menu_Data.CanBeQuickAction(action) then return false, Private.EditError.NotQuickAction end
    SetCenter(menu, CopyTable(action))
    Private.Changed()
    return true
end

--- Moves the center's action onto the wheel. It's inserted as action `index` (at the end when nil),
--- or with `replace` it takes the place of action `index`, which goes to the center (they swap). A
--- swap is refused for a submenu, which can't be in the center. An empty center does what Close
--- does (cancel), so it moves out as a Close action.
---@param id string|number
---@param index integer?
---@param replace boolean?
---@return boolean ok
---@return string? error why not, for the chat message
function Menu_Data.MoveQuickActionToWheel(id, index, replace)
    local menu, scopeOrError = Private.GetEditableMenu(id)
    if not menu then return false, scopeOrError end
    local action = Menu_Data.GetQuickAction(menu) or { kind = Menu_Kinds.Kind.Close }
    local replaced = replace and menu.actions[index]
    if replace and not replaced then return false, Private.EditError.ActionNotFound end
    if replaced and not Menu_Data.CanBeQuickAction(replaced) then return false, Private.EditError.NotQuickAction end
    -- Checked before the center changes, so a refused move leaves it as it was.
    local ok, err = Menu_Data.ValidateAction(menu.id, action)
    if not ok then return false, err end
    -- The replaced action leaves the wheel, so it moves to the center as it is.
    SetCenter(menu, replaced or nil)
    -- AddAction and ReplaceAction fire env.Event.DataChanged.
    if replace then return Menu_Data.ReplaceAction(id, index, action) end
    return Menu_Data.AddAction(id, action, index)
end
