--[[
    Ring data: the quick action (what a tap fires) and Last Used.

    ring.quickAction (Ring_Data.QuickAction): "none", or "custom": the action in the center
    (ring.quickSlice), fired by a tap and not on the wheel. A wedge dragged there is copied into
    it (the wedge stays); the center's action can be dragged out onto the wheel.
    Last Used there is a Last Used action (Kinds\LastUsed.lua). What each menu fired last is
    remembered here, on this character.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local Changed = Private.Changed

--- Identity of the slice last fired from ring `id` on this character (e.g. "item:6948"). Last Used
--- is stored by identity, not position, so it survives hidden slices and expanded nested rings
--- shifting the in-game positions.
function Ring_Data.GetLastUsedKey(id)
    return Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedSlice")[tostring(id)]
end

--- Remembers `key` (Ring_Data.GetSliceKey) as the slice last fired from ring `id` on this
--- character. Not a ring edit: fires "Ring.LastUsedChanged", not "Ring.DataChanged".
function Ring_Data.SetLastUsedKey(id, key)
    Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedSlice")[tostring(id)] = key
    CallbackRegistry.Trigger("Ring.LastUsedChanged", tostring(id))
end

--- The action a tap fires (in the center), or nil.
function Ring_Data.GetQuickActionSlice(ring)
    return ring.quickAction == Ring_Data.QuickAction.Custom and ring.quickSlice or nil
end

--- Empties the center: no quick action.
function Ring_Data.ClearQuickAction(id)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false end
    ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.None, nil
    Changed()
    return true
end

--- Why `slice` can't be in the center (Ring_Data.CanBeQuickAction): a submenu, or an action bar.
local function CantBeQuickError(slice)
    return slice.kind == "ring" and "a submenu can't be the quick action" or "an action bar can't be the quick action"
end

--- Puts `slice` (or nothing) in the center; NormalizeRing keeps Close there as an empty center.
local function SetCenter(ring, slice)
    ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.Custom, slice
    Private.NormalizeRing(ring)
end

--- Puts `slice` in the center: the ring's quick action (fired by a tap, not shown on the wheel).
--- @return boolean ok, string|nil error
function Ring_Data.SetQuickSlice(id, slice)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false, "menu not found" end
    if not Ring_Data.CanBeQuickAction(slice) then return false, CantBeQuickError(slice) end
    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end
    SetCenter(ring, slice)
    Changed()
    return true
end

--- Copies slice `index` into the center (it stays on the wheel), replacing what was there.
--- @return boolean ok, string|nil error
function Ring_Data.CopySliceToQuick(id, index)
    local ring = Ring_Data.GetRing(id)
    local slice = ring and ring.slices[index]
    if not slice then return false, "action not found" end
    if not Ring_Data.CanBeQuickAction(slice) then return false, CantBeQuickError(slice) end
    -- A copy: the wedge keeps its own.
    SetCenter(ring, CopyTable(slice))
    Changed()
    return true
end

--- Moves the center's action onto the wheel: inserted so it becomes slice `index` (nil = at the
--- end), or in place of slice `index` when `replace`, which then goes to the center (they swap;
--- refused for a submenu or action bar, which can't be in the center). An empty center does what
--- Close does (cancel), so it moves out as a Close action.
--- @return boolean ok, string|nil error
function Ring_Data.MoveQuickSliceToWheel(id, index, replace)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false, "menu not found" end
    if Ring_Data.IsBuiltIn(ring) then return false, Private.AUTO_ERROR end
    local slice = Ring_Data.GetQuickActionSlice(ring) or { kind = "close" }
    local replaced = replace and ring.slices[index]
    if replace and not replaced then return false, "action not found" end
    if replaced and not Ring_Data.CanBeQuickAction(replaced) then return false, CantBeQuickError(replaced) end
    -- Checked before the center changes, so a refused move leaves it as it was.
    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end
    -- The replaced action leaves the wheel, so it moves to the center as it is.
    SetCenter(ring, replaced or nil)
    -- AddSlice / ReplaceSlice fire "Ring.DataChanged".
    if replace then return Ring_Data.ReplaceSlice(id, index, slice) end
    return Ring_Data.AddSlice(id, slice, index)
end
