--[[
    targetmarker  id: raid target marker on your target (1 Star .. 8 Skull), or 0: clear every
                  target marker. Like the game's target marker wheel and /tm: using the marker your
                  target already has removes it. In a raid, only the leader and assistants can mark.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local CLEAR_ICON = "atlas:GM-raidMarker-reset" -- the raid manager's reset button

-- Offered in Add Action, and the Target Markers built-in menu's order: Skull at the top.
local MARKERS = { 8, 7, 6, 5, 4, 3, 2, 1, 0 }

Ring_Kinds.Register({
    kind = "targetmarker",
    noIconBorder = true, -- the marker art on its own, not a spell
    MARKERS = MARKERS,

    validate = function(slice)
        return type(slice.id) == "number" and slice.id >= 0 and slice.id <= 8, "target marker needs a number from 0 to 8"
    end,

    -- /tm is a secure command: works in combat. Clearing uses the secure button's own raid target
    -- action, which removes every target marker at once.
    apply = function(button, suffix, slice)
        if slice.id == 0 then
            Ring_Kinds.SetAttribute(button, "type", suffix, "raidtarget")
            Ring_Kinds.SetAttribute(button, "action", suffix, "clear-all")
        else
            Ring_Kinds.SetMacroText(button, suffix, "/tm " .. slice.id)
        end
    end,

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
