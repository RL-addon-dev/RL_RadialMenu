--[[
    Ring data: keybinds. They follow the menu's scope: account menus' keybinds are saved
    account-wide (Global_Persistent.Bindings), class menus' per class (Global_Persistent.
    ClassBindings), character menus' on the character (Local_Persistent.Bindings). A key belongs
    to one menu of each scope. Where menus of several scopes use it, the narrowest one's opens
    (Ring_Data.ScopeOrder; Ring_Secure binds them in that order): a character menu on its
    character, a class menu on that class's other characters, the account menu everywhere else.
]]

local env = select(2, ...)
local Config = env.Config
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local GetStoredTable, Changed = Private.GetStoredTable, Private.Changed

--- The table holding the keybind of a menu in `scope`.
function Private.GetBindingTable(scope)
    if scope == Ring_Data.Scope.Account then
        return GetStoredTable(Config.DBGlobalPersistent, "Bindings")
    elseif scope == Ring_Data.Scope.Class then
        return Private.GetClassStoredTable("ClassBindings")
    end
    return GetStoredTable(Config.DBLocalPersistent, "Bindings")
end
local GetBindingTable = Private.GetBindingTable

--- Takes `key` away from the other menus in `scope` (an account menu loses it on all characters).
--- Menus of other scopes keep it: the narrowest scope's menu opens either way.
local function ReleaseKey(key, exceptId, scope)
    local bindings = GetBindingTable(scope)
    for id, bound in pairs(bindings) do
        if id ~= exceptId and bound == key then bindings[id] = nil end
    end
end

--- A menu changed scope: its keybind moves with it.
function Private.MoveBinding(id, fromScope, toScope)
    local key = GetBindingTable(fromScope)[id]
    GetBindingTable(fromScope)[id] = nil
    if key then
        ReleaseKey(key, id, toScope)
        GetBindingTable(toScope)[id] = key
    end
end

--- @return string|nil key the menu's keybind
--- @return string|nil scope the menu's scope (Ring_Data.Scope), where its keybind is saved
function Ring_Data.GetBinding(id)
    id = tostring(id)
    local ring, scope = Ring_Data.GetRing(id)
    if not ring then return nil end
    return GetBindingTable(scope)[id], scope
end

--- Whether `scope` is narrower than `other` (its menu wins a key they share).
function Ring_Data.IsNarrowerScope(scope, other)
    return tIndexOf(Ring_Data.ScopeOrder, scope) > tIndexOf(Ring_Data.ScopeOrder, other)
end

--- The menus of narrower scopes that use menu `id`'s key here (each opens instead of `id` where
--- its scope applies), widest first.
--- @return table { { ring = ring, scope = scope }, ... } (empty when none does)
function Ring_Data.GetBindingOverrides(id)
    local overrides = {}
    local key, scope = Ring_Data.GetBinding(id)
    if not key then return overrides end
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

--- Menus that can be opened in game: those with a keybind, and the submenus they use (at any
--- depth). Other menus have nothing in game to keep current.
--- @return table rings in Ring_Data.GetRings order
--- @return table set [ringId] = true
function Ring_Data.GetOpenableRings()
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
    return rings, set
end

--- Sets (or clears, key = nil) a menu's keybind, saved for its scope. Other menus of that scope
--- using it lose it (see ReleaseKey).
function Ring_Data.SetBinding(id, key)
    local ring, scope = Ring_Data.GetRing(id)
    if not ring then return false end
    if key then ReleaseKey(key, ring.id, scope) end
    GetBindingTable(scope)[ring.id] = key
    Changed()
    return true
end
