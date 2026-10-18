--[[
    A raid target marker on a unit (1 Star to 8 Skull), or 0 to clear every target marker. Like the
    game's target marker wheel and /tm, using the marker the unit already has removes it. In a raid,
    only the leader and assistants can mark, so it's hidden there for everyone else
    (Utils_Unit.CanSetMarkers).

    Which unit it marks follows the Mark Target Markers On setting.
        - Cursor: on a tap (the quick action, also through Last Used or First Action), the unit
          under the mouse as it fires. Picked on the wheel, the unit under the mouse when the
          keybind was pressed, like a ping. Ring_Secure rewrites the slot's /tm for it, out of
          combat, for units with a lasting token (nameplate, target, focus, group).
        - Cursor + Focus: menus of only target markers mark any unit, in combat too, by making it
          your focus while open (Ring_Secure).
        - Otherwise, your target.
]]

---@class TargetMarkerSlice : Slice
---@field id number 1 Star to 8 Skull, or 0 to clear every target marker

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Unit = env.AX_Modules:Import("@\\Utils\\Unit")

local CLEAR = 0
local MAX_MARKER = 8

-- Offered in Add Action, and the Target Markers built-in menu's order, with Skull at the top.
local MARKERS = { 8, 7, 6, 5, 4, 3, 2, 1, CLEAR }
Ring_Kinds.TARGET_MARKERS = MARKERS

--- The /tm line for marker `id` on `unit`. Nil means your target, and "mouseover" the unit under
--- the mouse as it fires (your target when there's nothing there).
---@param id number
---@param unit string?
---@return string
function Ring_Kinds.GetTargetMarkerText(id, unit)
    if unit == "mouseover" then return format("/tm [@mouseover,exists][] %d", id) end
    return (unit and format("/tm [@%s] %d", unit, id)) or ("/tm " .. id)
end

--- Whether `slice` puts a marker on a unit (it isn't Clear).
---@param slice Slice
---@return boolean
function Ring_Kinds.IsUnitMarker(slice)
    return slice.kind == Ring_Kinds.Kind.TargetMarker and slice.id ~= CLEAR
end

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.TargetMarker,
    noIconBorder = true, -- the marker art on its own, not a spell

    validate = function(slice)
        return type(slice.id) == "number" and slice.id >= CLEAR and slice.id <= MAX_MARKER,
            L["Config - Rings - Edit - Error - TargetMarker"]
    end,

    -- /tm is a secure command, so it works in combat, and it takes a unit ([@nameplate3]) for
    -- Cursor. Clearing uses the secure button's own raid target action, which removes every target
    -- marker at once.
    apply = function(button, suffix, slice)
        if slice.id == CLEAR then
            Ring_Kinds.SetAttribute(button, "type", suffix, "raidtarget")
            Ring_Kinds.SetAttribute(button, "action", suffix, "clear-all")
        else
            Ring_Kinds.SetMacroText(button, suffix, Ring_Kinds.GetTargetMarkerText(slice.id))
        end
    end,

    condition = "targetmarker",
    available = function() return Utils_Unit.CanSetMarkers() end,

    icon = function(slice)
        return (slice.id == CLEAR and Ring_Kinds.CLEAR_MARKERS_ICON) or Ring_Kinds.RAID_TARGET_ICON:format(slice.id)
    end,
    label = function(slice)
        if slice.id == CLEAR then return L["Config - Rings - TargetMarker - Clear"] end
        return format(L["Config - Rings - TargetMarker - Name"], _G["RAID_TARGET_" .. slice.id] or tostring(slice.id))
    end,

    search = {
        filter = "markers",
        scan   = function(add)
            for _, id in ipairs(MARKERS) do add({ kind = Ring_Kinds.Kind.TargetMarker, id = id }) end
        end,
    },
})
