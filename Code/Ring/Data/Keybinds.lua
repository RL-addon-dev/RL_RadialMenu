--[[
    Ring data: keybinds. They follow the menu's scope: account menus' keybinds are saved
    account-wide (Global_Persistent.Bindings), character menus' keybinds on the character
    (Local_Persistent.Bindings). A key belongs to one account menu, and to one character menu on
    each character. When both use it, the character menu wins on its character (Ring_Secure binds
    character keys last) and the account menu opens everywhere else.
]]

local env = select(2, ...)
local Config = env.Config
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local GetStoredTable, Changed = Private.GetStoredTable, Private.Changed

function Private.GetCharacterBindingTable()
    return GetStoredTable(Config.DBLocalPersistent, "Bindings")
end

function Private.GetAccountBindingTable()
    return GetStoredTable(Config.DBGlobalPersistent, "Bindings")
end

--- The table holding the keybind of a menu in `scope`.
function Private.GetBindingTable(scope)
    return scope == Ring_Data.Scope.Account and Private.GetAccountBindingTable() or Private.GetCharacterBindingTable()
end
local GetBindingTable = Private.GetBindingTable

--- Takes `key` away from the other menus in `scope` (an account menu loses it on all characters).
--- Menus in the other scope keep it: a character menu's key wins on its character either way.
local function ReleaseKey(key, exceptId, scope)
    local bindings = GetBindingTable(scope)
    for id, bound in pairs(bindings) do
        if id ~= exceptId and bound == key then bindings[id] = nil end
    end
end

--- A menu changed scope: its keybind moves with it (account-wide <-> this character).
function Private.MoveBinding(id, fromScope, toScope)
    local key = GetBindingTable(fromScope)[id]
    GetBindingTable(fromScope)[id] = nil
    if key then
        ReleaseKey(key, id, toScope)
        GetBindingTable(toScope)[id] = key
    end
end

--- @return string|nil key the menu's keybind
--- @return boolean isAccount saved account-wide (an account menu)
function Ring_Data.GetBinding(id)
    id = tostring(id)
    local _, scope = Ring_Data.GetRing(id)
    return GetBindingTable(scope)[id], scope == Ring_Data.Scope.Account
end

--- The character menu that uses account menu `id`'s key on this character (it opens instead of
--- `id` here), or nil.
function Ring_Data.GetBindingOverride(id)
    local key, isAccount = Ring_Data.GetBinding(id)
    if not (key and isAccount) then return nil end
    for otherId, otherKey in pairs(Private.GetCharacterBindingTable()) do
        local other = otherKey == key and Ring_Data.GetRing(otherId)
        if other then return other end
    end
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

--- Sets (or clears, key = nil) a menu's keybind: account-wide for account menus, on this
--- character for character menus. Other menus using it lose it (see ReleaseKey).
function Ring_Data.SetBinding(id, key)
    local ring, scope = Ring_Data.GetRing(id)
    if not ring then return false end
    if key then ReleaseKey(key, ring.id, scope) end
    GetBindingTable(scope)[ring.id] = key
    Changed()
    return true
end
