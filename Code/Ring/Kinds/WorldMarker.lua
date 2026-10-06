--[[
    worldmarker  id: world (ground) marker 1 .. 8, placed where the mouse is when you release, or
                 with the game's targeting circle (the Place World Markers setting); 0 clears all
                 of them. Placing one that's already down moves it.
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local CLEAR_ICON = "atlas:GM-raidMarker-reset" -- the raid manager's reset button

-- World markers are numbered by color; the raid target icon each one shows on the ground.
local TARGET_ICON = {
    [1] = 6, -- blue square
    [2] = 4, -- green triangle
    [3] = 3, -- purple diamond
    [4] = 7, -- red cross
    [5] = 1, -- yellow star
    [6] = 2, -- orange circle
    [7] = 5, -- silver moon
    [8] = 8, -- white skull
}

-- Offered in Add Action, and the World Markers built-in menu's order: the same order of icons
-- as Target Markers (Skull at the top).
local MARKERS = { 8, 4, 1, 7, 2, 3, 6, 5, 0 }

Ring_Kinds.Register({
    kind = "worldmarker",
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

    icon = function(slice)
        return slice.id == 0 and CLEAR_ICON or ICON:format(TARGET_ICON[slice.id] or slice.id)
    end,
    label = function(slice)
        if slice.id == 0 then return L["Config - Rings - WorldMarker - Clear"] end
        local name = _G["RAID_TARGET_" .. (TARGET_ICON[slice.id] or slice.id)] or tostring(slice.id)
        return format(L["Config - Rings - WorldMarker - Name"], name)
    end,

    search = {
        filter = "markers",
        scan   = function(add)
            for _, id in ipairs(MARKERS) do add({ kind = "worldmarker", id = id }) end
        end,
    },
})
