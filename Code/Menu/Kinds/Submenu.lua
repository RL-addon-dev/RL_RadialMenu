--[[
    A submenu. It's scrolled with the mouse wheel, or spread into the parent menu with `spread`
    (Menu_Secure handles both, there's no click action). It's hidden while none of its own actions
    are shown.
]]

---@class SubmenuAction : Action
---@field menu string the submenu's Menu id
---@field nest nil an old field ("open" or "scroll" mode), cleared when found

local env = select(2, ...)
local L = env.L
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")
local Menu_Live = env.AX_Modules:Await("@\\Menu\\Live")

local ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local MAX_ICON_DEPTH = 3 -- how deep a submenu's icon looks into submenus inside it

--- The submenu, for its name and icon. That's this character's, else another class's or
--- character's. Those are shown in the settings and hidden in game, because the submenu doesn't
--- exist here and has nothing to show.
---@param id string
---@return Menu?
local function GetDisplayMenu(id)
    return Menu_Data.GetMenu(id) or (Menu_Data.GetElsewhereMenu(id))
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Submenu,

    ---@param action SubmenuAction
    validate = function(action, parentId)
        if Menu_Data.GetMenu(action.menu) == nil then return false, L["Config - Menus - Edit - Error - SubmenuGone"] end
        action.menu = tostring(action.menu)
        action.nest = nil
        if Menu_Data.WouldCreateCycle(tostring(parentId), action.menu) then
            return false, L["Config - Menus - Edit - Error - SubmenuLoop"]
        end
        return true
    end,

    apply = Menu_Kinds.ClearAction,

    -- The submenu's first action shown right now (else its first), like a folder preview. For an
    -- action bar, that's its first filled button.
    ---@param action SubmenuAction
    icon = function(action, depth)
        local menu = GetDisplayMenu(action.menu)
        if not menu or depth >= MAX_ICON_DEPTH then return ICON end
        for _, child in ipairs(menu.actions) do
            if Menu_Actions.IsActionAvailable(child, depth + 1) then return Menu_Actions.GetIcon(child, depth + 1) end
        end
        return (menu.actions[1] and Menu_Actions.GetIcon(menu.actions[1], depth + 1)) or ICON
    end,
    ---@param action SubmenuAction
    label = function(action)
        local menu = GetDisplayMenu(action.menu)
        return menu and menu.name
    end,

    -- A class or character menu says whose it is, in orange like the settings' other notes.
    ---@param action SubmenuAction
    tooltip = function(tooltip, action)
        tooltip:SetText(Menu_Actions.GetLabel(action), 1, 1, 1)
        local owner = Menu_Data.GetOwnerLabel(action.menu)
        if owner then tooltip:AddLine(owner, 1, 0.5, 0.25, true) end
        return true
    end,

    condition = "submenu",
    ---@param action SubmenuAction
    available = function(action, depth) return Menu_Live.HasShownActions(action.menu, depth) end,

    search = {
        filter  = "submenu",
        dynamic = true,
        -- Every other menu. Menus that already contain the one being edited are listed but
        -- `blocked`, because adding them would nest in a loop, so the user sees why they can't be
        -- added.
        scan    = function(add, menuId)
            for _, menu in ipairs(Menu_Data.GetMenus()) do
                if menu.id ~= menuId then
                    local candidate = add({ kind = Menu_Kinds.Kind.Submenu, menu = menu.id }, menu.name)
                    if candidate and Menu_Data.WouldCreateCycle(menuId, menu.id) then
                        candidate.blocked = L["Config - Menus - Search - Blocked - Loop"]
                    end
                end
            end
        end,
    },
})
