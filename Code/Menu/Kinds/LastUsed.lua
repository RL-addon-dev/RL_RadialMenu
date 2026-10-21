--[[
    Fires whatever this menu fired last, from any wedge or the center (as the quick action, double
    click the center). It has no fields of its own. Menu_Secure redirects its release to that
    action's slot ("*lastused-<suffix>", "menu-last"), so it's that action, not this one, that
    becomes the last used. Before anything was used, it does nothing. In game it shows the last
    action's icon while the menu is open (Menu_Secure), and elsewhere the question mark.
]]

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.LastUsed,

    apply = function(button, suffix)
        Menu_Kinds.ClearAction(button, suffix)
        Menu_Kinds.SetSlotAttribute(button, Menu_Kinds.ActionAttribute.LastUsed, suffix, true)
    end,

    icon  = function() return Menu_Kinds.QUESTION_MARK_ICON end,
    label = function() return L["Config - Menus - LastUsed"] end,

    tooltip = function(tooltip)
        return Menu_Kinds.SetTooltipText(tooltip, L["Config - Menus - LastUsed"], 
            L["Config - Menus - LastUsed - Description"])
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = Menu_Kinds.ScanOne(Menu_Kinds.Kind.LastUsed),
    },
})
