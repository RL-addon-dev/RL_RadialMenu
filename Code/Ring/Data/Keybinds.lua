--[[
    Ring data: keybinds. They follow the menu's scope.
        - Account menus' keybinds are saved account-wide (Global_Persistent.Bindings).
        - Class menus' keybinds are saved per class (Global_Persistent.ClassBindings).
        - Character menus' keybinds are saved on the character (Local_Persistent.Bindings).

    A key belongs to one menu of each scope. Where menus of several scopes use it, the narrowest
    one's opens (Ring_Data.ScopeOrder, which Ring_Secure binds in order). So a character menu opens
    on its character, a class menu on that class's other characters, and the account menu
    everywhere else.
]]

local env = select(2, ...)
local Config = env.Config
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local GetStoredTable, Changed = Private.GetStoredTable, Private.Changed

--- The keybinds of the menus in `scope`, by menu id.
---@param scope string a Ring_Data.Scope value
---@return table<string, string>
function Private.GetBindingTable(scope)
    if scope == Ring_Data.Scope.Account then
        return GetStoredTable(Config.DBGlobalPersistent, "Bindings")
    elseif scope == Ring_Data.Scope.Class then
        return Private.GetClassStoredTable("ClassBindings")
    end
    return GetStoredTable(Config.DBLocalPersistent, "Bindings")
end
local GetBindingTable = Private.GetBindingTable

--- Takes `key` away from the other menus in `scope`, so an account menu loses it on all
--- characters. Menus of other scopes keep it, because the narrowest scope's menu opens either way.
---@param key string
---@param exceptId string the menu getting the key
---@param scope string a Ring_Data.Scope value
local function ReleaseKey(key, exceptId, scope)
    local bindings = GetBindingTable(scope)
    for id, bound in pairs(bindings) do
        if id ~= exceptId and bound == key then bindings[id] = nil end
    end
end

--- Moves a menu's keybind along when the menu changes scope.
---@param id string
---@param fromScope string a Ring_Data.Scope value
---@param toScope string a Ring_Data.Scope value
function Private.MoveBinding(id, fromScope, toScope)
    local key = GetBindingTable(fromScope)[id]
    GetBindingTable(fromScope)[id] = nil
    if key then
        ReleaseKey(key, id, toScope)
        GetBindingTable(toScope)[id] = key
    end
end

--- Menu `id`'s keybind, and the scope it's saved in.
---@param id string|number
---@return string? key
---@return string? scope the menu's scope (Ring_Data.Scope)
function Ring_Data.GetBinding(id)
    id = tostring(id)
    local ring, scope = Ring_Data.GetRing(id)
    if not ring then return nil end
    return GetBindingTable(scope)[id], scope
end

--- Whether `scope` is narrower than `other`, so its menu wins a key they share.
---@param scope string a Ring_Data.Scope value
---@param other string a Ring_Data.Scope value
---@return boolean
function Ring_Data.IsNarrowerScope(scope, other)
    return tIndexOf(Ring_Data.ScopeOrder, scope) > tIndexOf(Ring_Data.ScopeOrder, other)
end

--- The menus of narrower scopes that use menu `id`'s key here, widest first. Each one opens
--- instead of `id` where its scope applies.
---@param id string|number
---@return { ring: Ring, scope: string }[] overrides empty when there are none
function Ring_Data.GetBindingOverrides(id)
    local overrides = {}
    local key, scope = Ring_Data.GetBinding(id)
    if not key or not scope then return overrides end
    for _, narrower in ipairs(Ring_Data.ScopeOrder) do
        if Ring_Data.IsNarrowerScope(narrower, scope) then
            for otherId, otherKey in pairs(GetBindingTable(narrower)) do
                local other = otherKey == key and Ring_Data.GetRing(otherId)
                if other then overrides[#overrides + 1] = { ring = other, scope = narrower } end
            end
        end
    end
    return overrides
end

-- GetOpenableRings' answer, kept until the menus change. Ring_Auto asks on every game state
-- update, and it only changes with menus, submenus and keybinds.
local openableRings, openableSet

--- Forgets the openable menus. Called just before env.Event.DataChanged and env.Event.DataReady
--- fire, so their listeners already get the new answer.
function Private.ForgetOpenableRings()
    openableRings, openableSet = nil, nil
end

--- The menus that can be opened in game, which are those with a keybind and the submenus they use
--- (at any depth). Other menus have nothing in game to keep current. The answer is cached, so
--- don't change the tables.
---@return Ring[] rings in Ring_Data.GetRings order
---@return table<string, boolean> set the same menus, by id
function Ring_Data.GetOpenableRings()
    if openableRings then return openableRings, openableSet end
    local set = {}
    local function Add(ring)
        if not ring or set[ring.id] then return end
        set[ring.id] = true
        for _, slice in ipairs(ring.slices) do
            if slice.kind == "ring" then Add(Ring_Data.GetRing(slice.ring)) end
        end
    end

    local all = Ring_Data.GetRings()
    for _, ring in ipairs(all) do
        if Ring_Data.GetBinding(ring.id) then Add(ring) end
    end

    local rings = {}
    for _, ring in ipairs(all) do
        if set[ring.id] then rings[#rings + 1] = ring end
    end
    openableRings, openableSet = rings, set
    return rings, set
end

--- Sets a menu's keybind, saved for its scope, or clears it when `key` is nil. Other menus of that
--- scope using the key lose it (see ReleaseKey).
---@param id string|number
---@param key string?
---@return boolean ok
function Ring_Data.SetBinding(id, key)
    local ring, scope = Ring_Data.GetRing(id)
    if not ring then return false end
    if key then ReleaseKey(key, ring.id, scope) end
    GetBindingTable(scope)[ring.id] = key
    Changed()
    return true
end
