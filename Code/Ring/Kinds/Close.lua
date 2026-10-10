--[[
    close   (no fields) closes the menu without using anything, like Escape or right click: for
            setups without those at hand (a controller, Relaxed style). Picking it is a cancel
            (Ring_Secure, "*close-<suffix>"): it fires nothing and never becomes Last Used. Put in
            the center, it's kept as an empty center, which does the same (Data\Store.lua,
            NormalizeRing).
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "atlas:Radial_Wheel_Icon_Close" -- the wheel's own cancel icon

Ring_Kinds.Register({
    kind = "close",
    noIconBorder = true, -- the wheel's X, not a spell

    validate = function() return true end,

    apply = function(button, suffix)
        Ring_Kinds.ClearAction(button, suffix)
        Ring_Kinds.SetAttribute(button, "close", suffix, true)
    end,

    icon  = function() return ICON end,
    label = function() return L["Config - Rings - Close"] end,

    tooltip = function(tooltip)
        tooltip:SetText(L["Config - Rings - Close"], 1, 1, 1)
        tooltip:AddLine(L["Config - Rings - Close - Description"], nil, nil, nil, true)
        return true
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = function(add) add({ kind = "close" }) end,
    },
})
