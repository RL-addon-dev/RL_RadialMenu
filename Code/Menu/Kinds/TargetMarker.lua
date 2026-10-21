--[[
    A raid target marker on a unit (1 Star to 8 Skull), or 0 to clear every target marker. Like the
    game's target marker wheel and /tm, using the marker the unit already has removes it. In a raid,
    only the leader and assistants can mark, so it's hidden there for everyone else
    (Utils_Unit.CanSetMarkers).

    Which unit it marks follows the Mark Target Markers On setting.
        - Cursor: on a tap (the quick action, also through Last Used or First Action), the unit
          under the mouse as it fires. Picked on the wheel, the unit under the mouse when the
          keybind was pressed, like a ping. Menu_Secure rewrites the slot's /tm for it, out of
          combat, for units with a lasting token (nameplate, target, focus, group).
        - Cursor + Focus: menus of only target markers mark any unit, in combat too, by making it
          your focus while open (Menu_Secure).
        - Otherwise, your target.
]]

---@class TargetMarkerAction : Action
---@field id number 1 Star to 8 Skull, or 0 to clear every target marker

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Unit = env.AX_Modules:Import("@\\Utils\\Unit")

local CLEAR = 0
local MAX_MARKER = 8

-- Offered in Add Action, and the Target Markers library menu's order, with Skull at the top.
local MARKERS = { 8, 7, 6, 5, 4, 3, 2, 1, CLEAR }
Menu_Kinds.TARGET_MARKERS = MARKERS

--- The /tm line for marker `id` on `unit`. Nil means your target, and "mouseover" the unit under
--- the mouse as it fires (your target when there's nothing there).
---@param id number
---@param unit string?
---@return string
function Menu_Kinds.GetTargetMarkerText(id, unit)
    if unit == "mouseover" then return format("/tm [@mouseover,exists][] %d", id) end
    return (unit and format("/tm [@%s] %d", unit, id)) or ("/tm " .. id)
end

--- Whether `action` puts a marker on a unit (it isn't Clear).
---@param action Action
---@return boolean
function Menu_Kinds.IsUnitMarker(action)
    return action.kind == Menu_Kinds.Kind.TargetMarker and action.id ~= CLEAR
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.TargetMarker,
    noIconBorder = true, -- the marker art on its own, not a spell

    validate = function(action)
        return type(action.id) == "number" and action.id >= CLEAR and action.id <= MAX_MARKER,
            L["Config - Menus - Edit - Error - TargetMarker"]
    end,

    -- /tm is a secure command, so it works in combat, and it takes a unit ([@nameplate3]) for
    -- Cursor. Clearing uses the secure button's own raid target action, which removes every target
    -- marker at once.
    apply = function(button, suffix, action)
        if action.id == CLEAR then
            Menu_Kinds.SetSlotAttribute(button, "type", suffix, "raidtarget")
            Menu_Kinds.SetSlotAttribute(button, "action", suffix, "clear-all")
        else
            Menu_Kinds.SetMacroText(button, suffix, Menu_Kinds.GetTargetMarkerText(action.id))
        end
    end,

    condition = "targetmarker",
    available = function() return Utils_Unit.CanSetMarkers() end,

    icon = function(action)
        return (action.id == CLEAR and Menu_Kinds.CLEAR_MARKERS_ICON) or Menu_Kinds.RAID_TARGET_ICON:format(action.id)
    end,
    label = function(action)
        if action.id == CLEAR then return L["Config - Menus - TargetMarker - Clear"] end
        return format(L["Config - Menus - TargetMarker - Name"], _G["RAID_TARGET_" .. action.id] or tostring(action.id))
    end,

    search = {
        filter = "markers",
        scan   = function(add)
            for _, id in ipairs(MARKERS) do add({ kind = Menu_Kinds.Kind.TargetMarker, id = id }) end
        end,
    },
})
