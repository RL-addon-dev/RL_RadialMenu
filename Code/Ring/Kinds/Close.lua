--[[
    Closes the menu without using anything, like Escape or right click, for setups without those at
    hand (a controller, Relaxed style). It has no fields of its own. Picking it is a cancel
    (Ring_Secure, "*close-<suffix>"), so it fires nothing and never becomes Last Used. Put in the
    center, it's kept as an empty center, which does the same (Data\Private.lua, NormalizeRing).
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "atlas:Radial_Wheel_Icon_Close" -- the wheel's own cancel icon

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Close,
    noIconBorder = true, -- the wheel's X, not a spell

    apply = function(button, suffix)
        Ring_Kinds.ClearAction(button, suffix)
        Ring_Kinds.SetAttribute(button, "close", suffix, true)
    end,

    icon  = function() return ICON end,
    label = function() return L["Config - Rings - Close"] end,

    tooltip = function(tooltip)
        return Ring_Kinds.SetTooltipText(tooltip, L["Config - Rings - Close"], L["Config - Rings - Close - Description"])
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = Ring_Kinds.ScanOne(Ring_Kinds.Kind.Close),
    },
})
