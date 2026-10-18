--[[
    Ring data: the quick action (what a tap fires) and Last Used.

    A menu's center holds its quick action when ring.quickAction is Ring_Data.QuickAction.Custom.
    That action (ring.quickSlice) fires on a tap and isn't on the wheel. A wedge dragged onto the
    center is copied there (the wedge stays), and the center's action can be dragged out onto the
    wheel. A Last Used center is a Last Used action (Kinds\LastUsed.lua). What each menu fired last
    is remembered here, on this character.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

--- The identity (Ring_Data.GetSliceKey) of the action last fired from menu `id` on this character,
--- like "item:6948". It's saved by identity, not position, so it survives hidden actions and
--- spread submenus shifting the positions in game.
---@param id string|number
---@return string?
function Ring_Data.GetLastUsedKey(id)
    return Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedSlice")[tostring(id)]
end

--- Remembers `key` (Ring_Data.GetSliceKey) as the action last fired from menu `id` on this
--- character. This isn't a menu edit, so it fires env.Event.LastUsedChanged instead of
--- env.Event.DataChanged.
---@param id string|number
---@param key string
function Ring_Data.SetLastUsedKey(id, key)
    Private.GetStoredTable(Config.DBLocalPersistent, "LastUsedSlice")[tostring(id)] = key
    CallbackRegistry.Trigger(env.Event.LastUsedChanged, tostring(id))
end

--- The action a tap fires (in the center), or nil.
---@param ring Ring
---@return Slice?
function Ring_Data.GetQuickActionSlice(ring)
    return (ring.quickAction == Ring_Data.QuickAction.Custom and ring.quickSlice) or nil
end

--- Empties the center, so the menu has no quick action.
---@param id string|number
---@return boolean ok
function Ring_Data.ClearQuickAction(id)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false end
    ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.None, nil
    Private.Changed()
    return true
end

--- Puts `slice`, or nothing, in the center. NormalizeRing keeps Close there as an empty center.
---@param ring Ring
---@param slice Slice?
local function SetCenter(ring, slice)
    ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.Custom, slice
    Private.NormalizeRing(ring)
end

--- Puts `slice` in the center as the menu's quick action, fired by a tap and not shown on the
--- wheel.
---@param id string|number
---@param slice Slice
---@return boolean ok
---@return string? error why not, for the chat message
function Ring_Data.SetQuickSlice(id, slice)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false, Private.EditError.MenuNotFound end
    if not Ring_Data.CanBeQuickAction(slice) then return false, Private.EditError.NotQuickAction end
    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end
    SetCenter(ring, slice)
    Private.Changed()
    return true
end

--- Copies action `index` into the center, replacing what was there. The action stays on the wheel.
---@param id string|number
---@param index integer
---@return boolean ok
---@return string? error why not, for the chat message
function Ring_Data.CopySliceToQuick(id, index)
    local ring = Ring_Data.GetRing(id)
    local slice = ring and ring.slices[index]
    if not slice then return false, Private.EditError.ActionNotFound end
    if not Ring_Data.CanBeQuickAction(slice) then return false, Private.EditError.NotQuickAction end
    SetCenter(ring, CopyTable(slice))
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
function Ring_Data.MoveQuickSliceToWheel(id, index, replace)
    local ring, scopeOrError = Private.GetEditableRing(id)
    if not ring then return false, scopeOrError end
    local slice = Ring_Data.GetQuickActionSlice(ring) or { kind = Ring_Kinds.Kind.Close }
    local replaced = replace and ring.slices[index]
    if replace and not replaced then return false, Private.EditError.ActionNotFound end
    if replaced and not Ring_Data.CanBeQuickAction(replaced) then return false, Private.EditError.NotQuickAction end
    -- Checked before the center changes, so a refused move leaves it as it was.
    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end
    -- The replaced action leaves the wheel, so it moves to the center as it is.
    SetCenter(ring, replaced or nil)
    -- AddSlice and ReplaceSlice fire env.Event.DataChanged.
    if replace then return Ring_Data.ReplaceSlice(id, index, slice) end
    return Ring_Data.AddSlice(id, slice, index)
end
