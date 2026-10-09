--[[
    Ring data: the quick action (what a tap fires) and Last Used.

    ring.quickAction (Ring_Data.QuickAction): "none", "last" (the slice last fired, on this
    character), a slice index, or "custom" (ring.quickSlice: tap-only, not on the wheel).
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local Changed = Private.Changed

--- Identity of the slice last fired from ring `id` on this character (e.g. "item:6948"). Last Used
--- is stored by identity, not position, so it survives hidden slices and expanded nested rings
--- shifting the in-game positions. Older saves stored a slice index; that is read as the slice at
--- that index.
function Ring_Data.GetLastUsedKey(id)
    local value = Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedSlice")[tostring(id)]
    if type(value) == "number" then
        local ring = Ring_Data.GetRing(id)
        local slice = ring and ring.slices[value]
        return slice and Ring_Data.GetSliceKey(slice)
    end
    return value
end

--- Remembers `key` (Ring_Data.GetSliceKey) as the slice last fired from ring `id` on this
--- character. Not a ring edit: fires "Ring.LastUsedChanged", not "Ring.DataChanged".
function Ring_Data.SetLastUsedKey(id, key)
    Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedSlice")[tostring(id)] = key
    CallbackRegistry.Trigger("Ring.LastUsedChanged", tostring(id))
end

--- Stored index of the last used slice when it's one of the ring's own slices (not a slice of an
--- expanded nested ring).
function Ring_Data.GetLastUsedSlice(id)
    local key = Ring_Data.GetLastUsedKey(id)
    local ring = Ring_Data.GetRing(id)
    if not (key and ring) then return nil end
    for index, slice in ipairs(ring.slices) do
        if Ring_Data.GetSliceKey(slice) == key then return index end
    end
end

--- Slice index a tap would fire right now, or nil (quick action None, or no slice used yet).
function Ring_Data.GetQuickActionIndex(ring)
    local index
    if ring.quickAction == Ring_Data.QuickAction.Last then
        index = Ring_Data.GetLastUsedSlice(ring.id)
    elseif type(ring.quickAction) == "number" then
        index = ring.quickAction
    end
    if index and ring.slices[index] then return index end
end

--- The slice a tap fires: a tap-only quick action, or one of the ring's slices.
--- @return table|nil slice
function Ring_Data.GetQuickActionSlice(ring)
    if ring.quickAction == Ring_Data.QuickAction.Custom then return ring.quickSlice end
    local index = Ring_Data.GetQuickActionIndex(ring)
    return index and ring.slices[index] or nil
end

--- Sets the quick action to None, Last Used, or one of the ring's slices (an index). For a
--- tap-only slice see SetQuickSlice.
function Ring_Data.SetQuickAction(id, value)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false end
    ring.quickAction = value
    Private.NormalizeRing(ring)
    Changed()
    return true
end

--- Makes `slice` the ring's tap-only quick action (fired by a tap, not shown on the wheel).
--- @return boolean ok, string|nil error
function Ring_Data.SetQuickSlice(id, slice)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false, "menu not found" end
    if not Ring_Data.CanBeQuickAction(slice) then return false, "a submenu or action bar can't be the quick action" end
    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end
    ring.quickAction = Ring_Data.QuickAction.Custom
    ring.quickSlice = slice
    Changed()
    return true
end

--- Moves the tap-only quick action onto the wheel: inserted so it becomes slice `index` (nil = at
--- the end), or in place of slice `index` when `replace`. The quick action becomes None.
--- @return boolean ok, string|nil error
function Ring_Data.MoveQuickSliceToWheel(id, index, replace)
    local ring = Ring_Data.GetRing(id)
    local slice = ring and ring.quickAction == Ring_Data.QuickAction.Custom and ring.quickSlice
    if not slice then return false, "no tap-only quick action" end
    if Ring_Data.IsBuiltIn(ring) then return false, Private.AUTO_ERROR end
    ring.quickAction = Ring_Data.QuickAction.None
    ring.quickSlice = nil
    -- AddSlice / ReplaceSlice fire "Ring.DataChanged".
    if replace then return Ring_Data.ReplaceSlice(id, index, slice) end
    return Ring_Data.AddSlice(id, slice, index)
end
