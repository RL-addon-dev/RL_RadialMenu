--[[
    Equips an item from your bags into an equipment slot (/equipslot). The link tells copies apart
    (upgrades, bonuses), and without it the first copy of the id is used. It's hidden while none is
    in your bags. The game only swaps weapons in combat.

    The Equip <Slot> library menus (Library\Equipment.lua) make these, and this file also lists
    those menus in Add Action.
]]

---@class EquipItemAction : Action
---@field id number the item id
---@field slot integer the equipment slot, 1 head to 19 tabard (18 ranged or relic on WoW Forever)
---@field link string? that copy's item link

local env = select(2, ...)
local L = env.L
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.EquipItem,

    ---@param action EquipItemAction
    validate = function(action)
        if type(action.id) ~= "number" then return false, L["Config - Menus - Edit - Error - EquipItem"] end
        return Utils_Item.IsEquipSlot(action.slot), L["Config - Menus - Edit - Error - EquipItemSlot"]
    end,

    -- The link's item string (item:id:enchant:..., the same copy), not the link itself, because
    -- its "[Name]" would read as macro conditions.
    ---@param action EquipItemAction
    apply = function(button, suffix, action)
        local item = (action.link and action.link:match("|H(item:[^|]+)|h")) or ("item:" .. action.id)
        Menu_Kinds.SetMacroText(button, suffix, "/equipslot " .. action.slot .. " " .. item)
    end,

    icon  = function(action) return C_Item.GetItemIconByID(action.id) end,
    label = function(action) return C_Item.GetItemNameByID(action.id) end,

    condition = "equipitem",
    available = function(action) return C_Item.GetItemCount(action.id) > Utils_Item.GetEquippedCount(action.id) end,

    ---@param action EquipItemAction
    tooltip = function(tooltip, action)
        if action.link then tooltip:SetHyperlink(action.link) else tooltip:SetItemByID(action.id) end
        tooltip:AddLine(format(L["Config - Menus - EquipItem - EquipsIn"], Utils_Item.GetSlotName(action.slot)), 1, 0.82, 0)
        return true
    end,
})

-- Search only (see Menu_Kinds.lua). The equipment library menus, as submenus, under the Equipment
-- filter. They're in Menus too, among every other menu.
Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.EquipMenus,

    search = {
        filter  = "equipment",
        label   = "submenu",
        dynamic = true, -- the menus' ids
        scan    = function(add)
            for _, key in ipairs(Menu_Data.EQUIP_MENU_KEYS or {}) do
                local menu = Menu_Data.GetLibraryMenu(key)
                if menu then add({ kind = Menu_Kinds.Kind.Submenu, menu = menu.id }, menu.name) end
            end
        end,
    },
})
