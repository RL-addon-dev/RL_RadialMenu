--[[
    lastused    (no fields) fires whatever this menu fired last, like the Last Used quick action,
                but from any wedge. Ring_Secure redirects its release to that action's slot
                ("*lastused-<suffix>", "ring-last"), so it's that action, not this one, that
                becomes the last used; before anything was used it does nothing. In game it
                shows the last action's icon while the menu is open (Ring_Secure); elsewhere it
                shows the question mark.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Kinds.Register({
    kind = "lastused",

    validate = function() return true end,

    apply = function(button, suffix)
        Ring_Kinds.ClearAction(button, suffix)
        Ring_Kinds.SetAttribute(button, "lastused", suffix, true)
    end,

    icon  = function() return Ring_Kinds.QUESTION_MARK_ICON end,
    label = function() return L["Config - Rings - LastUsed"] end,

    tooltip = function(tooltip)
        tooltip:SetText(L["Config - Rings - LastUsed"], 1, 1, 1)
        tooltip:AddLine(L["Config - Rings - LastUsed - Description"], nil, nil, nil, true)
        return true
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = function(add) add({ kind = "lastused" }) end,
    },
})
