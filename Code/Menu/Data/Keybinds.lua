--[[
    Menu data: keybinds. They follow the menu's scope.
        - Account menus' keybinds are saved account-wide (Global_Persistent.Bindings).
        - Class menus' keybinds are saved per class (Global_Persistent.ClassBindings).
        - Character menus' keybinds are saved on the character (Local_Persistent.Bindings).

    A key belongs to one menu of each scope. Where menus of several scopes use it, the narrowest
    one's opens (Menu_Data.ScopeOrder, which Menu_Secure binds in order). So a character menu opens
    on its character, a class menu on that class's other characters, and the account menu
    everywhere else.
]]

local env = select(2, ...)
local Config = env.Config
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

--- The keybinds of the menus in `scope`, by menu id.
---@param scope string a Menu_Data.Scope value
---@return table<string, string>
function Private.GetBindingTable(scope)
    if scope == Menu_Data.Scope.Account then
        return Private.GetStoredTable(Config.DBGlobalPersistent, "Bindings")
    elseif scope == Menu_Data.Scope.Class then
        return Private.GetClassStoredTable("ClassBindings")
    end
    return Private.GetStoredTable(Config.DBLocalPersistent, "Bindings")
end

--- Takes `key` away from the other menus in `scope`, so an account menu loses it on all
--- characters. Menus of other scopes keep it, because the narrowest scope's menu opens either way.
---@param key string
---@param exceptId string the menu getting the key
---@param scope string a Menu_Data.Scope value
local function ReleaseKey(key, exceptId, scope)
    local bindings = Private.GetBindingTable(scope)
    for id, bound in pairs(bindings) do
        if id ~= exceptId and bound == key then bindings[id] = nil end
    end
end

--- Moves a menu's keybind along when the menu changes scope.
---@param id string
---@param fromScope string a Menu_Data.Scope value
---@param toScope string a Menu_Data.Scope value
function Private.MoveBinding(id, fromScope, toScope)
    local key = Private.GetBindingTable(fromScope)[id]
    Private.GetBindingTable(fromScope)[id] = nil
    if key then
        ReleaseKey(key, id, toScope)
        Private.GetBindingTable(toScope)[id] = key
    end
end

--- Menu `id`'s keybind, and the scope it's saved in.
---@param id string|number
---@return string? key
---@return string? scope the menu's scope (Menu_Data.Scope)
function Menu_Data.GetBinding(id)
    id = tostring(id)
    local menu, scope = Menu_Data.GetMenu(id)
    if not menu then return nil end
    return Private.GetBindingTable(scope)[id], scope
end

--- Whether `scope` is narrower than `other`, so its menu wins a key they share.
---@param scope string a Menu_Data.Scope value
---@param other string a Menu_Data.Scope value
---@return boolean
function Menu_Data.IsNarrowerScope(scope, other)
    return tIndexOf(Menu_Data.ScopeOrder, scope) > tIndexOf(Menu_Data.ScopeOrder, other)
end

--- The menus of narrower scopes that use menu `id`'s key here, widest first. Each one opens
--- instead of `id` where its scope applies.
---@param id string|number
---@return { menu: Menu, scope: string }[] overrides empty when there are none
function Menu_Data.GetBindingOverrides(id)
    local overrides = {}
    local key, scope = Menu_Data.GetBinding(id)
    if not key or not scope then return overrides end
    for _, narrower in ipairs(Menu_Data.ScopeOrder) do
        if Menu_Data.IsNarrowerScope(narrower, scope) then
            for otherId, otherKey in pairs(Private.GetBindingTable(narrower)) do
                local other = otherKey == key and Menu_Data.GetMenu(otherId)
                if other then overrides[#overrides + 1] = { menu = other, scope = narrower } end
            end
        end
    end
    return overrides
end

-- GetOpenableMenus' answer, kept until the menus change. Menu_Auto asks on every game state
-- update, and it only changes with menus, submenus and keybinds.
local openableMenus, openableSet

--- Forgets the openable menus. Called just before env.Event.DataChanged and env.Event.DataReady
--- fire, so their listeners already get the new answer.
function Private.ForgetOpenableMenus()
    openableMenus, openableSet = nil, nil
end

--- The menus that can be opened in game, which are those with a keybind and the submenus they use
--- (at any depth). Other menus have nothing in game to keep current. The answer is cached, so
--- don't change the tables.
---@return Menu[] menus in Menu_Data.GetMenus order
---@return table<string, boolean> set the same menus, by id
function Menu_Data.GetOpenableMenus()
    if openableMenus then return openableMenus, openableSet end
    local set = {}
    local function Add(menu)
        if not menu or set[menu.id] then return end
        set[menu.id] = true
        for _, action in ipairs(menu.actions) do
            if action.kind == Menu_Kinds.Kind.Submenu then Add(Menu_Data.GetMenu(action.menu)) end
        end
    end

    local all = Menu_Data.GetMenus()
    for _, menu in ipairs(all) do
        if Menu_Data.GetBinding(menu.id) then Add(menu) end
    end

    local menus = {}
    for _, menu in ipairs(all) do
        if set[menu.id] then menus[#menus + 1] = menu end
    end
    openableMenus, openableSet = menus, set
    return menus, set
end

--- Sets a menu's keybind, saved for its scope, or clears it when `key` is nil. Other menus of that
--- scope using the key lose it (see ReleaseKey).
---@param id string|number
---@param key string?
---@return boolean ok
function Menu_Data.SetBinding(id, key)
    local menu, scope = Menu_Data.GetMenu(id)
    if not menu then return false end
    if key then ReleaseKey(key, menu.id, scope) end
    Private.GetBindingTable(scope)[menu.id] = key
    Private.Changed()
    return true
end
