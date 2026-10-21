--[[
    A world (ground) marker, 1 to 8, or 0 to clear all of them. It's placed where the mouse is when
    you release, or with the game's targeting circle (the Place World Markers setting). Placing one
    that's already down moves it. It only works in a group, and in a raid only for the leader and
    assistants, so it's hidden otherwise (Utils_Unit.CanSetMarkers).
]]

---@class WorldMarkerAction : Action
---@field id number the world marker, 1 to 8 (/wm 1 to 8), or 0 to clear all of them

local addonName, env = ...
local Config = env.Config
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Unit = env.AX_Modules:Import("@\\Utils\\Unit")

local CLEAR = 0
local MAX_MARKER = 8
-- The light behind each marker's icon (underlay), one white beam (Art\Menu\WorldMarkerBeam.png,
-- made by make_marker_beam.py) tinted per marker.
local BEAM = "Interface\\AddOns\\" .. addonName .. "\\Art\\Ring\\WorldMarkerBeam.png"

-- World markers by the game's number (/wm 1 to 8, action.id), with the raid target icon each shows
-- on the ground, and the color of its beam.
local MARKER = {
    [1] = { icon = 6, color = { 0.25, 0.55, 1.00 } }, -- blue square
    [2] = { icon = 4, color = { 0.25, 0.95, 0.35 } }, -- green triangle
    [3] = { icon = 3, color = { 0.80, 0.35, 1.00 } }, -- purple diamond
    [4] = { icon = 7, color = { 1.00, 0.25, 0.20 } }, -- red cross
    [5] = { icon = 1, color = { 1.00, 0.85, 0.20 } }, -- yellow star
    [6] = { icon = 2, color = { 1.00, 0.55, 0.15 } }, -- orange circle
    [7] = { icon = 5, color = { 0.82, 0.88, 1.00 } }, -- silver moon
    [8] = { icon = 8, color = { 1.00, 1.00, 1.00 } }, -- white skull
}

-- Clear shows the same icon as Target Markers' Clear, so its beam tells them apart. The beam is
-- neutral, as it clears every color.
local CLEAR_COLOR = { 0.85, 0.85, 0.85 }

-- Offered in Add Action, and the World Markers library menu's order. It's the same order of icons
-- as Target Markers, with Skull at the top.
local MARKERS = { 8, 4, 1, 7, 2, 3, 6, 5, CLEAR }
Menu_Kinds.WORLD_MARKERS = MARKERS

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.WorldMarker,
    noIconBorder = true, -- the marker art on its own, not a spell

    validate = function(action)
        return type(action.id) == "number" and action.id >= CLEAR and action.id <= MAX_MARKER,
            L["Config - Menus - Edit - Error - WorldMarker"]
    end,

    -- /wm and /cwm are secure commands, so they work in combat.
    apply = function(button, suffix, action)
        if action.id == CLEAR then
            Menu_Kinds.SetMacroText(button, suffix, "/cwm all") -- a number would clear only that marker
            return
        end
        -- The Place World Markers setting picks under the mouse (/wm [@cursor]), or the game's
        -- targeting circle. That's the secure button's own world marker action, like the raid
        -- manager's buttons (/wm without a target only errors when run from a button). With a
        -- controller (WoW Forever's gamepad UI) it's always the targeting circle, placed with the
        -- reticle.
        if Config.Get(Config.Key.WorldMarkerPlacement) == env.Enum.WorldMarkerPlacement.Click
            or env.IsGamepadUI() then
            Menu_Kinds.SetSlotAttribute(button, "type", suffix, "worldmarker")
            Menu_Kinds.SetSlotAttribute(button, "action", suffix, "set")
            Menu_Kinds.SetSlotAttribute(button, "marker", suffix, action.id)
        else
            Menu_Kinds.SetMacroText(button, suffix, "/wm [@cursor] " .. action.id)
        end
    end,

    condition = "worldmarker",
    available = function() return IsInGroup() and Utils_Unit.CanSetMarkers() end,

    icon = function(action)
        if action.id == CLEAR then return Menu_Kinds.CLEAR_MARKERS_ICON end
        local marker = MARKER[action.id]
        return Menu_Kinds.RAID_TARGET_ICON:format((marker and marker.icon) or action.id)
    end,
    -- A beam of light in the marker's color behind its icon. They're the same raid icons as target
    -- markers, so this tells them apart at a glance.
    underlay = function(action)
        if action.id == CLEAR then return BEAM, CLEAR_COLOR end
        local marker = MARKER[action.id]
        if marker then return BEAM, marker.color end
    end,
    label = function(action)
        if action.id == CLEAR then return L["Config - Menus - WorldMarker - Clear"] end
        local marker = MARKER[action.id]
        local name = _G["RAID_TARGET_" .. ((marker and marker.icon) or action.id)] or tostring(action.id)
        return format(L["Config - Menus - WorldMarker - Name"], name)
    end,

    search = {
        filter = "markers",
        scan   = function(add)
            for _, id in ipairs(MARKERS) do add({ kind = Menu_Kinds.Kind.WorldMarker, id = id }) end
        end,
    },
})
