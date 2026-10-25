--[[
    Menu data: library menus. They always exist (created at load) and are account-wide. They can't
    be renamed, deleted or added to by hand, because Menu_Auto fills them. The user can rearrange
    them, and that order is remembered by action identity (menu.order) across refills.

    The user can remove actions too. They're remembered by identity in menu.removed, with a name and
    icon for showing them while they aren't around, and left out of every refill until restored.
    New actions still appear.

    Each library menu is one file in Code\Menu\Library\ (listed in Library.xml). Here's an
    example, and Types.lua (LibraryDefinition) describes each field.

        Menu_Data.RegisterLibraryMenu({
            key      = "quest",                                -- saved as menu.library, never renamed
            name     = "Config - Menus - QuestMenu - Name",     -- the locale key of its fixed name
            events   = { "QUEST_LOG_UPDATE", ... },            -- it refills after these (Menu_Auto)
            scan     = function() return actions end,          -- what it holds right now
            category = Menu_Data.LibraryCategory.Situational,  -- its Library group (Situational by default)
            versions = { env.GameVersion.Retail },             -- the games it exists in (every one by default)
        })

    Keys are one lowercase word ("targetmarkers"), like action kind names and for the same reason
    (see Menu_Kinds.lua). They're saved data, so renaming one after release needs a migration, or
    the menu is deleted and recreated and loses its keybind and order.

    The text an empty library menu shows is the optional locale string
    "Config - Menus - Auto - Empty - <key>". A library menu for other game versions isn't
    registered, so it has no menu and no events. Its versions must be ones where every action kind
    it uses exists (Menu_Kinds.lua). Library menus whose key isn't registered (retired, or not for
    this game) are removed at load. Each game version keeps its own saved variables.
]]

local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")

local definitions, order = {}, {}

-- Library groups for the library menus (definition.category). The values are saved, because the
-- settings keep each group's open or closed state as "category:<value>", and they name the locale
-- string "Config - Menus - Library - <value>". Never rename one.
Menu_Data.LibraryCategory = Utils_Standard.Strict({
    ActionBars  = "actionbars",
    Character   = "character",
    Consumables = "consumables",
    Equipment   = "equipment",
    Markers     = "markers",
    Situational = "situational",
    Travel      = "travel"
}, "library category")
-- The order the settings list them in.
Menu_Data.LibraryCategoryOrder = {
    Menu_Data.LibraryCategory.ActionBars, Menu_Data.LibraryCategory.Character,
    Menu_Data.LibraryCategory.Consumables, Menu_Data.LibraryCategory.Equipment,
    Menu_Data.LibraryCategory.Markers, Menu_Data.LibraryCategory.Situational,
    Menu_Data.LibraryCategory.Travel
}

--- Registers a library menu (see the header). Called by each Code\Menu\Library\ file.
---@param definition LibraryDefinition
function Menu_Data.RegisterLibraryMenu(definition)
    assert(type(definition.key) == "string" and type(definition.scan) == "function", "library menu needs a key and a scan")
    assert(definition.category == nil or tIndexOf(Menu_Data.LibraryCategoryOrder, definition.category),
        "library menu has an unknown category (Menu_Data.LibraryCategory): " .. definition.key)
    if not env.IsForThisGame(definition.versions) then return end
    assert(not definitions[definition.key], "library menu registered twice: " .. definition.key)
    definitions[definition.key] = definition
    order[#order + 1] = definition
end

--- The Library group of library menu `menu`, from its definition. Situational when it has none.
---@param menu Menu?
---@return string category a Menu_Data.LibraryCategory value
function Menu_Data.GetLibraryCategory(menu)
    local definition = menu and menu.library and definitions[menu.library]
    return (definition and definition.category) or Menu_Data.LibraryCategory.Situational
end

--- Every library menu definition, in registration order.
---@return LibraryDefinition[]
function Menu_Data.GetLibraryDefinitions()
    return order
end

--- This character's library menu with key `key` (menu.library), or nil.
---@param key string
---@return Menu?
function Menu_Data.GetLibraryMenu(key)
    for _, menu in ipairs(Menu_Data.GetMenus()) do
        if menu.library == key then return menu end
    end
end

--- Whether `menu` is a library menu. Those always exist and fill themselves, so they can't be
--- deleted, made per character, renamed, or have actions added or removed by hand.
---@param menu Menu?
---@return boolean
function Menu_Data.IsLibraryMenu(menu)
    return menu ~= nil and menu.library ~= nil
end

--- One action of `kind` per value, for a library menu's scan. Each value goes in `field` (`id`
--- by default), and `fields` adds the same extra fields to every action. For example,
--- MakeActions(Menu_Kinds.Kind.Spell, spellIDs, nil, { byId = true }).
---@param kind string a Menu_Kinds.Kind value
---@param values any[]
---@param field string? the action's field for the value (`id` by default)
---@param fields table? fields every action gets
---@return Action[]
function Menu_Data.MakeActions(kind, values, field, fields)
    local actions = {}
    for index, value in ipairs(values) do
        local action = { kind = kind, [field or "id"] = value }
        for key, extra in pairs(fields or {}) do action[key] = extra end
        actions[index] = action
    end
    return actions
end

--- Menu_Auto's refill of a library menu. It fires env.Event.DataChanged with
--- env.ChangeReason.Auto, so the secure rebuild it causes (after combat, if needed) doesn't
--- announce itself. What refers to an action by position, like a remembered scroll position,
--- follows the action to its new position, or is dropped when the action is gone. A submenu keeps
--- its spread or scroll setting (action.spread), which the user can change on library menus too.
---@param id string|number
---@param actions Action[]
---@return boolean ok false when `id` isn't a library menu
function Menu_Data.SetAutoActions(id, actions)
    local menu = Menu_Data.GetMenu(id)
    if not Menu_Data.IsLibraryMenu(menu) then return false end

    local newIndex = {}
    for index, action in ipairs(actions) do
        local key = Menu_Data.GetActionKey(action)
        newIndex[key] = newIndex[key] or index
    end
    local oldActions = menu.actions
    local spreadByKey = {}
    for _, action in ipairs(oldActions) do
        if action.spread then spreadByKey[Menu_Data.GetActionKey(action)] = true end
    end
    for _, action in ipairs(actions) do
        if spreadByKey[Menu_Data.GetActionKey(action)] then action.spread = true end
    end
    Private.RemapActionIndices(menu, function(index)
        local action = oldActions[index]
        return action and newIndex[Menu_Data.GetActionKey(action)]
    end)

    menu.actions = actions
    Private.NormalizeMenu(menu)
    -- Its submenus may have changed (Consumables), so the openable menus are worked out again.
    Private.Changed(env.ChangeReason.Auto)
    return true
end

--- Something the menus show changed outside the menu data (the zone ability), so they rebuild
--- quietly.
function Menu_Data.NotifyDynamicChange()
    CallbackRegistry.Trigger(env.Event.DataChanged, env.ChangeReason.Auto)
end



-- Refilling

--- Whether two action lists hold the same actions in the same order.
---@param a Action[]
---@param b Action[]
---@return boolean
local function SameActions(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if Menu_Data.GetActionKey(a[i]) ~= Menu_Data.GetActionKey(b[i]) then return false end
    end
    return true
end

--- Fills library menu `menu` from its definition. That's what it holds now, minus the actions the
--- user removed, in the order they arranged (new actions at the end). Menu_Auto calls it after the
--- definition's events, and restoring an action calls it at once.
---@param menu Menu
function Menu_Data.RefillLibraryMenu(menu)
    local definition = menu.library and definitions[menu.library]
    if not definition then return end
    local removed = {}
    for _, entry in ipairs(menu.removed or {}) do removed[entry.key] = true end
    local actions = {}
    for _, action in ipairs(definition.scan()) do
        if not removed[Menu_Data.GetActionKey(action)] then actions[#actions + 1] = action end
    end
    actions = Menu_Data.ApplyAutoOrder(menu, actions)
    if not SameActions(menu.actions, actions) then Menu_Data.SetAutoActions(menu.id, actions) end
end



-- Removed actions

--- The actions removed from library menu `menu`, oldest first.
---@param menu Menu?
---@return RemovedAction[]
function Menu_Data.GetRemovedActions(menu)
    return (menu and menu.removed) or {}
end

--- Remembers `action` as removed from library menu `menu` (Menu_Data.RemoveAction), with its name
--- and icon as they are now.
---@param menu Menu
---@param action Action
function Private.RememberRemoved(menu, action)
    local key = Menu_Data.GetActionKey(action)
    menu.removed = menu.removed or {}
    for _, entry in ipairs(menu.removed) do
        if entry.key == key then return end
    end
    menu.removed[#menu.removed + 1] = { key = key, label = Menu_Actions.GetLabel(action), icon = Menu_Actions.GetIcon(action) }
end

--- Puts removed action `key` back into library menu `id`, or every removed action when `key` is
--- nil. It shows again at the next refill, which happens now.
---@param id string|number
---@param key string?
---@return boolean ok
function Menu_Data.RestoreRemoved(id, key)
    local menu = Menu_Data.GetMenu(id)
    if not (Menu_Data.IsLibraryMenu(menu) and menu.removed) then return false end
    if key then
        for index = #menu.removed, 1, -1 do
            if menu.removed[index].key == key then table.remove(menu.removed, index) end
        end
    else
        wipe(menu.removed)
    end
    if #menu.removed == 0 then menu.removed = nil end
    Menu_Data.RefillLibraryMenu(menu)
    Private.Changed() -- the removed list changed, whether or not the menu did
    return true
end



-- Remembered order

--- Remembers a library menu's order by action identity, so Menu_Auto's refills keep it. Actions
--- not in the menu right now (a quest item you used up) keep their place in the remembered order,
--- after the ones that are.
---@param menu Menu
function Private.RememberAutoOrder(menu)
    if not Menu_Data.IsLibraryMenu(menu) then return end
    local keys, seen = {}, {}
    local function Add(key)
        if seen[key] then return end
        seen[key] = true
        keys[#keys + 1] = key
    end
    for _, action in ipairs(menu.actions) do Add(Menu_Data.GetActionKey(action)) end
    for _, key in ipairs(menu.order or {}) do Add(key) end
    menu.order = keys
end

--- Sorts a library menu's freshly scanned actions into its remembered order. Actions it hasn't
--- seen yet go at the end, in the order they were scanned.
---@param menu Menu
---@param actions Action[] sorted in place
---@return Action[] actions
function Menu_Data.ApplyAutoOrder(menu, actions)
    local rank = {}
    for index, key in ipairs(menu.order or {}) do rank[key] = index end
    local scanned = {}
    for index, action in ipairs(actions) do scanned[action] = index end
    table.sort(actions, function(a, b)
        local rankA, rankB = rank[Menu_Data.GetActionKey(a)], rank[Menu_Data.GetActionKey(b)]
        if rankA and rankB then return rankA < rankB end
        if rankA or rankB then return rankA ~= nil end
        return scanned[a] < scanned[b]
    end)
    return actions
end



-- Creating them

--- Makes sure every registered library menu exists (as an account menu, named in the client's
--- language), and removes library menus that aren't registered any more.
function Private.EnsureLibraryMenus()
    local existing = {}
    for _, menu in ipairs(Menu_Data.GetMenus()) do
        if menu.library and not definitions[menu.library] then
            menu.library = nil -- DeleteMenu refuses library menus
            Menu_Data.DeleteMenu(menu.id)
        elseif menu.library then
            existing[menu.library] = menu
        end
    end

    for _, definition in ipairs(order) do
        local name = env.L[definition.name] or definition.key
        local menu = existing[definition.key]
        if menu then
            menu.name = name
        else
            Menu_Data.CreateMenu(name, Menu_Data.Scope.Account, { library = definition.key, actions = {} })
        end
    end
end
