--[[
    Fires whatever the menu's first wedge would. That's the first action shown on this character
    (hidden actions, and other characters' or classes' submenus, aren't there), skipping Close,
    Last Used and First actions. It has no fields of its own. A scrolling submenu fires the action
    it shows, and a spread one's actions are on the wheel already. So one account menu's quick
    action can do something different on each character.

    Ring_Secure redirects its release to that wedge's slot ("*first-<suffix>", "ring-first", found
    at every rebuild), so that action becomes the last used. With no such wedge it does nothing. In
    game it shows that action's icon while the menu is open (Ring_Secure), and elsewhere its own
    icon (Art\Icon\FirstAction.png).
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Path = env.AX_Modules:Import("ax_modules\\path")

-- A menu wheel with its top wedge lit (Art\Icon\make_slice_icon.py).
local ICON_PATH = "%s\\Art\\Icon\\FirstAction.png"

-- Actions that fire nothing of their own, or only point at another, so never a First Action's
-- target.
local NOT_FIRST = { [Ring_Kinds.Kind.Close] = true, [Ring_Kinds.Kind.LastUsed] = true, [Ring_Kinds.Kind.First] = true }

--- Whether a First Action can fire `slice` (it can't fire a Close, Last Used or First action).
---@param slice Slice
---@return boolean
function Ring_Kinds.CanBeFirst(slice)
    return not NOT_FIRST[slice.kind]
end

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.First,

    apply = function(button, suffix)
        Ring_Kinds.ClearAction(button, suffix)
        Ring_Kinds.SetAttribute(button, Ring_Kinds.ActionAttribute.First, suffix, true)
    end,

    icon  = function() return ICON_PATH:format(Path.Root) end,
    label = function() return L["Config - Rings - First"] end,

    tooltip = function(tooltip)
        return Ring_Kinds.SetTooltipText(tooltip, L["Config - Rings - First"], 
            L["Config - Rings - First - Description"])
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = Ring_Kinds.ScanOne(Ring_Kinds.Kind.First),
    },
})
