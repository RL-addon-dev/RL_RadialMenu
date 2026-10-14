--[[
    worldmarker  id: world (ground) marker 1 .. 8, placed where the mouse is when you release, or
                 with the game's targeting circle (the Place World Markers setting); 0 clears all
                 of them. Placing one that's already down moves it. Only in a group (and in a
                 raid, for the leader and assistants): hidden otherwise (Ring_Kinds.CanSetMarkers).
]]

local addonName, env = ...
local Config = env.Config
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
-- The light behind each marker's icon (underlay): one white beam (Art\Ring\WorldMarkerBeam.png,
-- made by make_marker_beam.py), tinted per marker.
local BEAM = "Interface\\AddOns\\" .. addonName .. "\\Art\\Ring\\WorldMarkerBeam.png"

-- World markers by the game's number (/wm 1 .. 8, slice.id): the raid target icon each shows on
-- the ground, and the color of its beam.
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

-- Clear (id 0): the raid manager's reset button, the same icon as Target Markers' Clear, so its
-- beam tells them apart; neutral, as it clears every color.
local CLEAR = { icon = "atlas:GM-raidMarker-reset", color = { 0.85, 0.85, 0.85 } }

-- Offered in Add Action, and the World Markers built-in menu's order: the same order of icons
-- as Target Markers (Skull at the top).
local MARKERS = { 8, 4, 1, 7, 2, 3, 6, 5, 0 }

Ring_Kinds.Register({
    kind = "worldmarker",
    noIconBorder = true, -- the marker art on its own, not a spell
    MARKERS = MARKERS,

    validate = function(slice)
        return type(slice.id) == "number" and slice.id >= 0 and slice.id <= 8, "world marker needs a number from 0 to 8"
    end,

    -- /wm and /cwm are secure commands: they work in combat.
    apply = function(button, suffix, slice)
        if slice.id == 0 then
            Ring_Kinds.SetMacroText(button, suffix, "/cwm all") -- a number would clear only that marker
        else
            -- Place World Markers setting: under the mouse (/wm [@cursor]), or the game's targeting
            -- circle: the secure button's own world marker action, like the raid manager's buttons
            -- (/wm without a target only errors when run from a button).
            if Config.DBGlobal:GetVariable("WorldMarkerPlacement") == env.Enum.WorldMarkerPlacement.Click then
                Ring_Kinds.SetAttribute(button, "type", suffix, "worldmarker")
                Ring_Kinds.SetAttribute(button, "action", suffix, "set")
                Ring_Kinds.SetAttribute(button, "marker", suffix, slice.id)
            else
                Ring_Kinds.SetMacroText(button, suffix, "/wm [@cursor] " .. slice.id)
            end
        end
    end,

    condition = "worldmarker",
    available = function() return IsInGroup() and Ring_Kinds.CanSetMarkers() end,

    icon = function(slice)
        if slice.id == 0 then return CLEAR.icon end
        local marker = MARKER[slice.id]
        return ICON:format(marker and marker.icon or slice.id)
    end,
    -- A beam of light in the marker's color behind its icon: the same raid icons as target
    -- markers, told apart at a glance.
    underlay = function(slice)
        if slice.id == 0 then return BEAM, CLEAR.color end
        local marker = MARKER[slice.id]
        if marker then return BEAM, marker.color end
    end,
    label = function(slice)
        if slice.id == 0 then return L["Config - Rings - WorldMarker - Clear"] end
        local marker = MARKER[slice.id]
        local name = _G["RAID_TARGET_" .. (marker and marker.icon or slice.id)] or tostring(slice.id)
        return format(L["Config - Rings - WorldMarker - Name"], name)
    end,

    search = {
        filter = "markers",
        scan   = function(add)
            for _, id in ipairs(MARKERS) do add({ kind = "worldmarker", id = id }) end
        end,
    },
})
