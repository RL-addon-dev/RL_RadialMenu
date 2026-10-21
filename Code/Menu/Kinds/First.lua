--[[
    Fires whatever the menu's first wedge would. That's the first action shown on this character
    (hidden actions, and other characters' or classes' submenus, aren't there), skipping Close,
    Last Used and First actions. It has no fields of its own. A scrolling submenu fires the action
    it shows, and a spread one's actions are on the wheel already. So one account menu's quick
    action can do something different on each character.

    Menu_Secure redirects its release to that wedge's slot ("*first-<suffix>", "menu-first", found
    at every rebuild), so that action becomes the last used. With no such wedge it does nothing. In
    game it shows that action's icon while the menu is open (Menu_Secure), and elsewhere its own
    icon (Art\Icon\FirstAction.png).
]]

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Path = env.AX_Modules:Import("ax_modules\\path")

-- A menu wheel with its top wedge lit (Art\Icon\make_action_icon.py).
local ICON_PATH = "%s\\Art\\Icon\\FirstAction.png"

-- Actions that fire nothing of their own, or only point at another, so never a First Action's
-- target.
local NOT_FIRST = { [Menu_Kinds.Kind.Close] = true, [Menu_Kinds.Kind.LastUsed] = true, [Menu_Kinds.Kind.First] = true }

--- Whether a First Action can fire `action` (it can't fire a Close, Last Used or First action).
---@param action Action
---@return boolean
function Menu_Kinds.CanBeFirst(action)
    return not NOT_FIRST[action.kind]
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.First,

    apply = function(button, suffix)
        Menu_Kinds.ClearAction(button, suffix)
        Menu_Kinds.SetSlotAttribute(button, Menu_Kinds.ActionAttribute.First, suffix, true)
    end,

    icon  = function() return ICON_PATH:format(Path.Root) end,
    label = function() return L["Config - Menus - First"] end,

    tooltip = function(tooltip)
        return Menu_Kinds.SetTooltipText(tooltip, L["Config - Menus - First"], 
            L["Config - Menus - First - Description"])
    end,

    search = {
        filter = "misc",
        label  = "special",
        scan   = Menu_Kinds.ScanOne(Menu_Kinds.Kind.First),
    },
})
