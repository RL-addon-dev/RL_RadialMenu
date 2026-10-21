--[[
    Menu data: the store. Queries about menus, and the edits to menus and their actions.

    Menu_Data is one module spread over Code\Menu\Data\ (listed in Data.xml).
        Private.lua      helpers the other files share (the Private module, not public)
        Store.lua        this file, with queries and menu and action edits
        Keybinds.lua     keybinds, which follow the menu's scope
        QuickAction.lua  the quick action (a tap) and Last Used
        Library.lua      library menus, with their automatic contents and remembered order
        Share.lua        sharing menus as text (share string, import plan, import)
        Elsewhere.lua    other classes' and characters' menus, read-only in the settings
        Startup.lua      start-up, with saved-data migrations (Migrations\), first-run menus and
                         library menus

    Menus are saved in the persistent databases, so the settings' Reset doesn't delete them.
        RL_RadialMenuDB_Global_Persistent.Menus            [id] = menu          account menus
        RL_RadialMenuDB_Global_Persistent.ClassMenus       [class][id] = menu   class menus (class file name)
        RL_RadialMenuDB_Local_Persistent.Menus             [id] = menu          character menus
        RL_RadialMenuDB_Global_Persistent.Bindings         [id] = key           keybinds of account menus
        RL_RadialMenuDB_Global_Persistent.ClassBindings    [class][id] = key    keybinds of class menus
        RL_RadialMenuDB_Local_Persistent.Bindings          [id] = key           keybinds of character menus
        RL_RadialMenuDB_Global_Persistent.NextMenuId                            id counter, unique across scopes
        RL_RadialMenuDB_Local_Persistent.LastUsedAction    [id] = action key    what each menu fired last
        RL_RadialMenuDB_Local_Persistent.ScrollIndex       ["id:index"] = n     a scroll submenu's shown action

    A menu applies to all characters (account), the characters of one class (class) or one
    character. That scope is where it's stored, not a field on the menu. The fields of menus and
    actions are described in Types.lua (Menu, Action).

    Every edit fires env.Event.DataChanged.
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Display = env.AX_Modules:Await("@\\Menu\\Display")

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local min, max = math.min, math.max

-- Who a menu applies to (see the header).
Menu_Data.Scope = Utils_Standard.Strict({
    Account   = "account",
    Class     = "class",
    Character = "character"
}, "scope")
-- Widest to narrowest. Where menus of several scopes use one key, the narrowest one's opens
-- (Menu_Secure binds them in this order).
Menu_Data.ScopeOrder = { Menu_Data.Scope.Account, Menu_Data.Scope.Class, Menu_Data.Scope.Character }

Menu_Data.MIN_PROBE_DISTANCE = 1

-- Settings every menu shares (General tab)

--- Seconds before a held menu's wheel shows.
---@return number
function Menu_Data.GetRevealDelay()
    return Config.Get(Config.Key.RevealDelay)
end

--- Distance to Select, the pixels moved from the key-down spot before an action is picked.
---@return number
function Menu_Data.GetDeadzone()
    return Config.Get(Config.Key.Deadzone)
end

--- The side of the square around the key-down spot. Distance to Cancel Quick Action is half of it,
--- the distance moved before the center switches from the quick action to cancel. When selecting
--- from the cursor, it's at most Distance to Select, so its edges never reach past it. Once you've
--- been out picking an action, coming back to the center cancels. With Select From set to Menu
--- Center, the two are measured from different spots, so there's no cap.
---@return number
function Menu_Data.GetProbeSize()
    local distance = max(Config.Get(Config.Key.ProbeSize), Menu_Data.MIN_PROBE_DISTANCE)
    if not Menu_Display.IsSelectFromMenu() then distance = min(distance, Menu_Data.GetDeadzone()) end
    return 2 * distance
end

--- A new menu id, unique across scopes and characters.
---@return string
local function NextMenuId()
    local stored = Config.DBGlobalPersistent:GetData()
    local nextId = tonumber(stored.NextMenuId) or 1
    while Menu_Data.GetMenu(tostring(nextId)) do nextId = nextId + 1 end
    stored.NextMenuId = nextId + 1
    return tostring(nextId)
end

-- Queries

--- This character's menu `id`, and its scope.
---@param id string|number?
---@return Menu? menu
---@return string? scope a Menu_Data.Scope value
function Menu_Data.GetMenu(id)
    if id == nil then return nil end
    id = tostring(id)
    for _, scope in ipairs(Menu_Data.ScopeOrder) do
        local menu = Private.GetScopeTable(scope)[id]
        if menu then return menu, scope end
    end
end

--- Every menu this character has, sorted by name, then id.
---@return Menu[]
function Menu_Data.GetMenus()
    local menus = {}
    for _, scope in ipairs(Menu_Data.ScopeOrder) do
        for _, menu in pairs(Private.GetScopeTable(scope)) do
            menus[#menus + 1] = menu
        end
    end
    table.sort(menus, function(a, b)
        local nameA, nameB = Private.SortName(a), Private.SortName(b)
        if nameA ~= nameB then return nameA < nameB end
        return a.id < b.id
    end)
    return menus
end

--- The class name in locale string `key` (which has a %s, like "%ss" for "Mages"), in the class
--- color when `colored`. A class menu only exists for its own class, so that's always the
--- player's.
---@param key string
---@param colored boolean?
---@return string
local function ClassText(key, colored)
    local name, class = UnitClass("player")
    local text = format(L[key], name)
    local color = colored and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return (color and color.WrapTextInColorCode and color:WrapTextInColorCode(text)) or text
end

--- The name of `scope` in the settings' Available On choice, such as "Account", "Mages" or
--- "This Character".
---@param scope string a Menu_Data.Scope value
---@return string
function Menu_Data.GetScopeName(scope)
    if scope == Menu_Data.Scope.Class then return ClassText("Config - Menus - Scope - Class") end
    if scope == Menu_Data.Scope.Character then return L["Config - Menus - Scope - Character"] end
    return L["Config - Menus - Scope - Account"]
end

--- Where a class or character menu applies, such as "your Mages" or "this character". Nil for an
--- account menu, which applies everywhere.
---@param scope string a Menu_Data.Scope value
---@return string?
function Menu_Data.GetScopeWhere(scope)
    if scope == Menu_Data.Scope.Class then
        return format(L["Config - Menus - Scope - Where - Class"], ClassText("Config - Menus - Scope - Class", true))
    elseif scope == Menu_Data.Scope.Character then
        return L["Config - Menus - Scope - Where - Character"]
    end
end

--- Whose menu `id` is, for its tooltip, such as "Nevergryn's menu" or "Mage menu". Works for this
--- character's menus and those of other classes and characters (Elsewhere.lua). Nil for an account
--- menu.
---@param id string|number
---@return string?
function Menu_Data.GetOwnerLabel(id)
    local _, scope = Menu_Data.GetMenu(id)
    if scope == Menu_Data.Scope.Character then
        return format(L["Config - Menus - CharacterMenu"], UnitName("player"))
    elseif scope == Menu_Data.Scope.Class then
        return format(L["Config - Menus - ClassMenu"], (UnitClass("player")))
    end
    local _, owner = Menu_Data.GetElsewhereMenu(id)
    if owner and owner.character then
        return format(L["Config - Menus - CharacterMenu"], owner.character.name or "?")
    elseif owner then
        local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[owner.class] or owner.class
        return format(L["Config - Menus - ClassMenu"], className)
    end
end

--- Whether `action` is a submenu this character doesn't have, meaning another class's or another
--- character's menu inside an account menu. It only exists for them, so it's hidden in game and
--- shown as hidden in the settings' preview.
---@param action Action
---@return boolean
function Menu_Data.IsElsewhere(action)
    return action.kind == Menu_Kinds.Kind.Submenu and Menu_Data.GetMenu(action.menu) == nil
end

--- Whether `action` can be a quick action. Submenus can't, because they hold several actions and a
--- tap has no single one to fire.
---@param action Action
---@return boolean
function Menu_Data.CanBeQuickAction(action)
    return action.kind ~= Menu_Kinds.Kind.Submenu
end

--- The identity of an action, the same across refills and moves, like "item:6948". Last Used and
--- library menus' remembered order use it.
---@param action Action
---@return string
function Menu_Data.GetActionKey(action)
    -- Works for every kind, so it reads whichever kind's identity field the action has.
    local fields = action --[[@as table]]
    local value = fields.id or fields.command or fields.slot or fields.guid or fields.menu
        or fields.token or fields.home or fields.name
    -- An action bar ("actionbar:2"), or one of its buttons ("actionslot:2-5").
    if fields.bar then value = (fields.button and (fields.bar .. "-" .. fields.button)) or fields.bar end
    -- A highest-rank spell isn't the same action as the rank its id names.
    return fields.kind .. ":" .. tostring(value) .. ((fields.anyRank and ":any") or "")
end

--- Which action a scroll submenu shows, remembered on this character (1 when never scrolled).
---@param menuId string|number the menu holding the submenu
---@param actionIndex integer the submenu's index in it
---@return integer
function Menu_Data.GetScrollIndex(menuId, actionIndex)
    local stored = Private.GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    return stored[tostring(menuId) .. ":" .. actionIndex] or 1
end

--- Remembers which action a scroll submenu shows. This isn't a menu edit, so it doesn't fire
--- env.Event.DataChanged.
---@param menuId string|number
---@param actionIndex integer
---@param childIndex integer
function Menu_Data.SetScrollIndex(menuId, actionIndex, childIndex)
    local stored = Private.GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    stored[tostring(menuId) .. ":" .. actionIndex] = childIndex
end

--- Whether adding menu `childId` as a submenu of `parentId` would make them contain each other.
---@param parentId string
---@param childId string|number
---@return boolean
function Menu_Data.WouldCreateCycle(parentId, childId)
    local visited = {}
    local function Reaches(menuId)
        if menuId == parentId then return true end
        if visited[menuId] then return false end
        visited[menuId] = true

        local menu = Menu_Data.GetMenu(menuId)
        if not menu then return false end
        for _, action in ipairs(menu.actions) do
            if action.kind == Menu_Kinds.Kind.Submenu and Reaches(tostring(action.menu)) then return true end
        end
        return false
    end
    return Reaches(tostring(childId))
end

--- Checks (and normalizes) an action about to be saved in menu `parentId`, with its kind's
--- `validate`.
---@param parentId string? nil when it isn't in a menu yet (imports)
---@param action Action
---@return boolean ok
---@return string? error why not, for the chat message
function Menu_Data.ValidateAction(parentId, action)
    local definition = type(action) == "table" and Menu_Kinds.Get(action.kind)
    if not definition then return false, format(Private.EditError.UnknownKind, tostring(action and action.kind)) end
    if not definition.validate then return true end
    return definition.validate(action, parentId)
end

-- Menu edits

--- Creates a menu in `scope`.
---@param name string?
---@param scope string? a Menu_Data.Scope value (Account by default)
---@param template table? fields to start from, copied (actions, quickAction, library, ...)
---@return Menu
function Menu_Data.CreateMenu(name, scope, template)
    local menu = (template and CopyTable(template)) or {}
    menu.id = NextMenuId()
    menu.name = name or menu.name or L["Config - Menus - NewMenu - DefaultName"]
    menu.binding = nil -- keybinds live in the binding tables (Keybinds.lua)
    Private.NormalizeMenu(menu)

    Private.GetScopeTable(scope or Menu_Data.Scope.Account)[menu.id] = menu
    Private.Changed()
    return menu
end

--- Deletes menu `id`, and removes it as a submenu from this character's menus. Submenu links in
--- other characters' or classes' menus stay, and are ignored (Menu_Data.IsElsewhere).
---@param id string|number
---@return boolean ok false for a library menu, or one that doesn't exist
function Menu_Data.DeleteMenu(id)
    local menu, scope = Private.GetEditableMenu(id)
    if not menu then return false end

    Private.GetScopeTable(scope)[menu.id] = nil
    Private.GetBindingTable(scope)[menu.id] = nil

    for _, other in ipairs(Menu_Data.GetMenus()) do
        for i = #other.actions, 1, -1 do
            local action = other.actions[i]
            if action.kind == Menu_Kinds.Kind.Submenu and tostring(action.menu) == menu.id then
                table.remove(other.actions, i)
                Private.ShiftAfterRemove(other, i)
            end
        end
        Private.NormalizeMenu(other)
    end

    Private.Changed()
    return true
end

--- Moves menu `id` to another scope. Its keybind moves with it.
---@param id string|number
---@param scope string a Menu_Data.Scope value
---@return boolean ok
function Menu_Data.SetScope(id, scope)
    local menu, currentScope = Private.GetEditableMenu(id)
    if not menu or currentScope == scope then return false end

    Private.GetScopeTable(currentScope)[menu.id] = nil
    Private.GetScopeTable(scope)[menu.id] = menu
    Private.MoveBinding(menu.id, currentScope, scope)
    Private.Changed()
    return true
end

---@param id string|number
---@param name string
---@return boolean ok
function Menu_Data.RenameMenu(id, name)
    local menu = Private.GetEditableMenu(id)
    if not menu then return false end
    menu.name = name
    Private.Changed()
    return true
end

-- Action edits

--- Adds `action` to menu `id`.
---@param id string|number
---@param action Action
---@param index integer? the position it gets (at the end by default)
---@return boolean ok
---@return string? error why not, for the chat message
function Menu_Data.AddAction(id, action, index)
    local menu, scopeOrError = Private.GetEditableMenu(id)
    if not menu then return false, scopeOrError end

    local ok, err = Menu_Data.ValidateAction(menu.id, action)
    if not ok then return false, err end

    local count = #menu.actions
    index = (index and Clamp(index, 1, count + 1)) or (count + 1)
    if index <= count then Private.ShiftAfterInsert(menu, index) end

    table.insert(menu.actions, index, action)
    Private.Changed()
    return true
end

--- Moves an action so it ends up at position `to`. The others shift to make room.
---@param id string|number
---@param from integer
---@param to integer
---@return boolean ok
function Menu_Data.MoveAction(id, from, to)
    local menu = Menu_Data.GetMenu(id)
    if not menu or not menu.actions[from] then return false end

    to = Clamp(to, 1, #menu.actions)
    if from == to then return false end

    table.insert(menu.actions, to, table.remove(menu.actions, from))
    Private.RemapActionIndices(menu, function(i)
        if i == from then return to end
        if from < to and i > from and i <= to then return i - 1 end
        if from > to and i >= to and i < from then return i + 1 end
        return i
    end)
    Private.RememberAutoOrder(menu)

    Private.Changed()
    return true
end

--- Swaps two actions' positions.
---@param id string|number
---@param a integer
---@param b integer
---@return boolean ok
function Menu_Data.SwapActions(id, a, b)
    local menu = Menu_Data.GetMenu(id)
    if not menu or a == b or not menu.actions[a] or not menu.actions[b] then return false end

    menu.actions[a], menu.actions[b] = menu.actions[b], menu.actions[a]
    Private.RemapActionIndices(menu, function(i)
        if i == a then return b end
        if i == b then return a end
        return i
    end)
    Private.RememberAutoOrder(menu)

    Private.Changed()
    return true
end

--- Puts `action` in place of action `index`, like dropping onto an action bar slot. What referred
--- to the replaced action (the quick action, Last Used, a scroll position) is dropped.
---@param id string|number
---@param index integer
---@param action Action
---@return boolean ok
---@return string? error why not, for the chat message
function Menu_Data.ReplaceAction(id, index, action)
    local menu, scopeOrError = Private.GetEditableMenu(id)
    if not menu then return false, scopeOrError end
    if not menu.actions[index] then return false, Private.EditError.ActionNotFound end

    local ok, err = Menu_Data.ValidateAction(menu.id, action)
    if not ok then return false, err end

    menu.actions[index] = action
    Private.RemapActionIndices(menu, function(i) return (i ~= index and i) or nil end)

    Private.NormalizeMenu(menu)
    Private.Changed()
    return true
end

--- Whether submenu action `index` spreads its actions into the menu (`spread`) or scrolls, which
--- is the default.
---@param id string|number
---@param index integer
---@param spread boolean
---@return boolean ok
function Menu_Data.SetSubmenuSpread(id, index, spread)
    local menu = Menu_Data.GetMenu(id)
    local action = menu and menu.actions[index]
    if not action or action.kind ~= Menu_Kinds.Kind.Submenu then return false end
    action.spread = spread and true or nil
    Private.Changed()
    return true
end

--- Removes action `index`. From a library menu, it's also left out of its refills until restored
--- (Library.lua).
---@param id string|number
---@param index integer
---@return boolean ok
function Menu_Data.RemoveAction(id, index)
    local menu = Menu_Data.GetMenu(id)
    if not menu or not menu.actions[index] then return false end

    if Menu_Data.IsLibraryMenu(menu) then Private.RememberRemoved(menu, menu.actions[index]) end

    table.remove(menu.actions, index)
    Private.ShiftAfterRemove(menu, index)

    Private.NormalizeMenu(menu)
    Private.Changed()
    return true
end
