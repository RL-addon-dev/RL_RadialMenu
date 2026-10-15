--[[
    targetmarker  id: raid target marker on your target (1 Star .. 8 Skull), or 0: clear every
                  target marker. Like the game's target marker wheel and /tm: using the marker your
                  target already has removes it. In a raid, only the leader and assistants can mark,
                  so it's hidden there for everyone else (Ring_Kinds.CanSetMarkers).
                  Mark Target Markers On = Cursor: on a tap (the quick action, also through Last
                  Used or First Action), the unit under the mouse as it fires; picked on the
                  wheel, the unit under the mouse when the keybind was pressed, like a ping
                  (Ring_Secure rewrites the slot's /tm for it, out of combat, for units with a
                  lasting token: nameplate, target, focus, group). Otherwise your target.
                  Cursor + Focus: menus of only target markers mark any unit, in combat too, by
                  making it your focus while open (Ring_Secure).
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local CLEAR_ICON = "atlas:GM-raidMarker-reset" -- the raid manager's reset button

-- Offered in Add Action, and the Target Markers built-in menu's order: Skull at the top.
local MARKERS = { 8, 7, 6, 5, 4, 3, 2, 1, 0 }

--- Whether you may set target and world markers in your group: anyone solo or in a party; in a
--- raid only the leader and assistants (or everyone, with "everyone is assistant"). World markers
--- also need a group (WorldMarker.lua). Rebuilt on group changes (Ring_Auto).
function Ring_Kinds.CanSetMarkers()
    if not IsInRaid() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
        or (IsEveryoneAssistant and IsEveryoneAssistant()) or false
end

--- The /tm line for marker `id` on `unit`: nil for your target, "mouseover" for the unit under
--- the mouse as it fires (your target with nothing there).
function Ring_Kinds.GetTargetMarkerText(id, unit)
    if unit == "mouseover" then return format("/tm [@mouseover,exists][] %d", id) end
    return unit and format("/tm [@%s] %d", unit, id) or ("/tm " .. id)
end

--- Whether `slice` puts a marker on a unit (not Clear).
function Ring_Kinds.IsUnitMarker(slice)
    return slice.kind == "targetmarker" and slice.id ~= 0
end

--- Whether `unit` is the unit under the mouse. UnitIsUnit, not GUIDs: Midnight can hide a unit's
--- GUID (a secret value) even out of combat. A secret answer counts as no.
local function IsMouseover(unit)
    local same = UnitIsUnit(unit, "mouseover")
    if issecretvalue and issecretvalue(same) then return false end
    return same and true or false
end

--- A unit token for the unit under the mouse that still names it once the mouse moves away (its
--- nameplate, target, focus, a group member, you), or nil: nothing under the mouse, or no such
--- token. Out of combat (Ring_Secure, when a menu opens).
function Ring_Kinds.GetUnitUnderMouse()
    local candidates = { "target", "focus", "player" }
    -- Nameplate tokens directly (nameplate1..40), not through the plate frames: those can carry no
    -- token (nameplate addons, or Midnight).
    for index = 1, 40 do
        local unit = "nameplate" .. index
        local exists = UnitExists(unit)
        if exists and not (issecretvalue and issecretvalue(exists)) then candidates[#candidates + 1] = unit end
    end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for index = 1, count do candidates[#candidates + 1] = prefix .. index end

    for _, unit in ipairs(candidates) do
        if IsMouseover(unit) then return unit end
    end
end

Ring_Kinds.Register({
    kind = "targetmarker",
    noIconBorder = true, -- the marker art on its own, not a spell
    MARKERS = MARKERS,

    validate = function(slice)
        return type(slice.id) == "number" and slice.id >= 0 and slice.id <= 8, "target marker needs a number from 0 to 8"
    end,

    -- /tm is a secure command: works in combat, and takes a unit ([@nameplate3]) for Cursor.
    -- Clearing uses the secure button's own raid target action, which removes every target marker
    -- at once.
    apply = function(button, suffix, slice)
        if slice.id == 0 then
            Ring_Kinds.SetAttribute(button, "type", suffix, "raidtarget")
            Ring_Kinds.SetAttribute(button, "action", suffix, "clear-all")
        else
            Ring_Kinds.SetMacroText(button, suffix, Ring_Kinds.GetTargetMarkerText(slice.id))
        end
    end,

    condition = "targetmarker",
    available = function() return Ring_Kinds.CanSetMarkers() end,

    icon = function(slice)
        return slice.id == 0 and CLEAR_ICON or ICON:format(slice.id)
    end,
    label = function(slice)
        if slice.id == 0 then return L["Config - Rings - TargetMarker - Clear"] end
        return format(L["Config - Rings - TargetMarker - Name"], _G["RAID_TARGET_" .. slice.id] or tostring(slice.id))
    end,

    search = {
        filter = "markers",
        scan   = function(add)
            for _, id in ipairs(MARKERS) do add({ kind = "targetmarker", id = id }) end
        end,
    },
})
