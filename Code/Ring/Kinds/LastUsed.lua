--[[
    Fires whatever this menu fired last, from any wedge or the center (as the quick action, double
    click the center). It has no fields of its own. Ring_Secure redirects its release to that
    action's slot ("*lastused-<suffix>", "ring-last"), so it's that action, not this one, that
    becomes the last used. Before anything was used, it does nothing. In game it shows the last
    action's icon while the menu is open (Ring_Secure), and elsewhere the question mark.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.LastUsed,

    apply = function(button, suffix)
        Ring_Kinds.ClearAction(button, suffix)
        Ring_Kinds.SetAttribute(button, Ring_Kinds.ActionAttribute.LastUsed, suffix, true)
    end,

    icon  = function() return Ring_Kinds.QUESTION_MARK_ICON end,
    label = function() return L["Config - Rings - LastUsed"] end,

    tooltip = function(tooltip)
        return Ring_Kinds.SetTooltipText(tooltip, L["Config - Rings - LastUsed"], 
            L["Config - Rings - LastUsed - Description"])
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = Ring_Kinds.ScanOne(Ring_Kinds.Kind.LastUsed),
    },
})
