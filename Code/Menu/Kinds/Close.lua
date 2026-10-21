--[[
    Closes the menu without using anything, like Escape or right click, for setups without those at
    hand (a controller, Relaxed style). It has no fields of its own. Picking it is a cancel
    (Menu_Secure, "*close-<suffix>"), so it fires nothing and never becomes Last Used. Put in the
    center, it's kept as an empty center, which does the same (Data\Private.lua, NormalizeMenu).
]]

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

local ICON = "atlas:Radial_Wheel_Icon_Close" -- the wheel's own cancel icon

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Close,
    noIconBorder = true, -- the wheel's X, not a spell

    apply = function(button, suffix)
        Menu_Kinds.ClearAction(button, suffix)
        Menu_Kinds.SetSlotAttribute(button, Menu_Kinds.ActionAttribute.Close, suffix, true)
    end,

    icon  = function() return ICON end,
    label = function() return L["Config - Menus - Close"] end,

    tooltip = function(tooltip)
        return Menu_Kinds.SetTooltipText(tooltip, L["Config - Menus - Close"], L["Config - Menus - Close - Description"])
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = Menu_Kinds.ScanOne(Menu_Kinds.Kind.Close),
    },
})
