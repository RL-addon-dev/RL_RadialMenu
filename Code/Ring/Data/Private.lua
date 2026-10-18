--[[
    Ring data: the helpers its files share, in the Private module. The rest of the addon uses the
    public Ring_Data functions instead.

    Loads first in Data.xml, so it creates both modules. The helpers cover these things.
        - Saved tables: where menus, keybinds and other menu data are stored (Store.lua's header
          lists them).
        - Change notification: Changed, after every menu edit.
        - Keeping menus consistent: NormalizeRing, and moving remembered scroll positions along
          when actions move.
        - Small shared lookups: the player's class, a menu the user can edit, sorting by name.
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Data = env.AX_Modules:New("@\\Ring\\Data")
local Private = env.AX_Modules:New("@\\Ring\\Data\\Private")

local type, pairs, ipairs, tonumber = type, pairs, ipairs, tonumber

-- Fields menus no longer have. These are per menu settings that became global ones, and
-- `contents` (how a menu was filled, now only built-in menus fill themselves, by their `builtin` key).
local REMOVED_RING_FIELDS = { "revealDelay", "deadzone", "probeSize", "contents" }

-- Why an edit was refused. The settings print it in chat, like "Couldn't add action: menu not found".
Private.EditError = {
    MenuNotFound    = L["Config - Rings - Edit - Error - MenuNotFound"],
    ActionNotFound  = L["Config - Rings - Edit - Error - ActionNotFound"],
    BuiltIn         = L["Config - Rings - Edit - Error - BuiltIn"],
    NotQuickAction  = L["Config - Rings - Edit - Error - NotQuickAction"],
    UnknownKind     = L["Config - Rings - Edit - Error - UnknownKind"], -- format with the kind
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
---@param scope string a Ring_Data.Scope value
---@return table<string, Ring>
function Private.GetScopeTable(scope)
    if scope == Ring_Data.Scope.Character then
        return Private.GetStoredTable(Config.DBLocalPersistent, "Rings")
    elseif scope == Ring_Data.Scope.Class then
        return Private.GetClassStoredTable("ClassRings")
    end
    return Private.GetStoredTable(Config.DBGlobalPersistent, "Rings")
end

-- Changes

--- Announces a menu edit with env.Event.DataChanged. The openable menus are forgotten first, so
--- listeners already get the new ones.
---@param reason string? an env.ChangeReason value, nil for an edit by hand
function Private.Changed(reason)
    Private.ForgetOpenableRings()
    CallbackRegistry.Trigger(env.Event.DataChanged, reason)
end

--- Menu `id` when the user can edit it by hand, which built-in menus can't be.
---@param id string|number
---@return Ring? ring nil when it can't be edited
---@return string scopeOrError its scope (Ring_Data.Scope), or why it can't be edited (Private.EditError)
function Private.GetEditableRing(id)
    local ring, scope = Ring_Data.GetRing(id)
    if not ring then return nil, Private.EditError.MenuNotFound end
    if Ring_Data.IsBuiltIn(ring) then return nil, Private.EditError.BuiltIn end
    return ring, scope
end

--- Fills defaults and drops what a menu may no longer hold. Run after every edit that could leave
--- a menu inconsistent.
---@param ring Ring
function Private.NormalizeRing(ring)
    -- New menus start without a quick action. Releasing in the center then cancels, so an action
    -- used last (a Hearthstone, a potion) doesn't fire again by accident.
    if ring.quickAction == nil then ring.quickAction = Ring_Data.QuickAction.None end
    for _, key in ipairs(REMOVED_RING_FIELDS) do
        ring[key] = nil
    end
    if type(ring.slices) ~= "table" then ring.slices = {} end
    -- Submenus used to have an "open" or "scroll" mode. They always scroll now.
    for _, slice in ipairs(ring.slices) do
        if slice.kind == Ring_Kinds.Kind.Ring then slice.nest = nil end
    end
    -- quickSlice only exists while quickAction is Custom. Close in the center is saved as an empty
    -- center, because both cancel, and an empty one toggles with Last Used and has no X.
    if ring.quickAction == Ring_Data.QuickAction.Custom
        and (type(ring.quickSlice) ~= "table" or ring.quickSlice.kind == Ring_Kinds.Kind.Close) then
        ring.quickAction = Ring_Data.QuickAction.None
    end
    if ring.quickAction ~= Ring_Data.QuickAction.Custom then ring.quickSlice = nil end
end

-- Remembered scroll positions

--- After actions move, keeps each remembered scroll position (saved by action index) on the same
--- action.
---@param ring Ring
---@param map fun(oldIndex: integer): integer? the new index, or nil when that action is gone
function Private.RemapSliceIndices(ring, map)
    local scroll = Private.GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    local prefix = ring.id .. ":"
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
---@param ring Ring
---@param index integer
function Private.ShiftAfterInsert(ring, index)
    Private.RemapSliceIndices(ring, function(i) return (i >= index and i + 1) or i end)
end

--- Keeps scroll positions on their actions after action `index` is removed (its own is dropped).
---@param ring Ring
---@param index integer
function Private.ShiftAfterRemove(ring, index)
    Private.RemapSliceIndices(ring, function(i)
        if i == index then return nil end
        return (i > index and i - 1) or i
    end)
end

-- Sorting

--- A menu's name for sorting, so lists ignore case.
---@param ring Ring
---@return string
function Private.SortName(ring)
    return (ring.name or ""):lower()
end
