--[[
    Equip <Slot>: a library menu per equipment slot (Equip Head to Equip Off Hand, and Equip
    Ranged on WoW Forever), holding the items in your bags you can use there. They're listed in Add
    Action under Equipment with Equipment Sets (EquipmentSets.lua), to add as submenus, which scroll,
    or spread with a double click.

    Slot menus list what's in your bags, once per copy (item link), so what you're wearing isn't
    there. They refill together from one bag scan (Utils_Item.GetBagItemsBySlot) as bags, gear and
    your level change.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

-- Each slot's library menu key (saved data, never renamed).
local SLOT_KEYS = {
    [1] = "equiphead", [2] = "equipneck", [3] = "equipshoulder", [4] = "equipshirt", [5] = "equipchest",
    [6] = "equipwaist", [7] = "equiplegs", [8] = "equipfeet", [9] = "equipwrist", [10] = "equiphands",
    [11] = "equipring1", [12] = "equipring2", [13] = "equiptrinket1", [14] = "equiptrinket2",
    [15] = "equipback", [16] = "equipmainhand", [17] = "equipoffhand", [18] = "equipranged",
    [19] = "equiptabard",
}

-- The menus Add Action lists under Equipment, in this order (Kinds\EquipItem.lua). That's
-- Equipment Sets (EquipmentSets.lua), then the slots.
Menu_Data.EQUIP_MENU_KEYS = { "equipsets" }

for _, slot in ipairs(Utils_Item.EQUIP_SLOTS) do
    local key = SLOT_KEYS[slot]
    table.insert(Menu_Data.EQUIP_MENU_KEYS, key)
    Menu_Data.RegisterLibraryMenu({
        key      = key,
        category = Menu_Data.LibraryCategory.Equipment,
        name     = "Config - Menus - EquipMenu - " .. slot, -- one locale string per slot
        events   = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" },
        scan     = function()
            local actions = {}
            for _, item in ipairs(Utils_Item.GetBagItemsBySlot()[slot]) do
                actions[#actions + 1] = { kind = Menu_Kinds.Kind.EquipItem, id = item.id, slot = slot, link = item.link }
            end
            return actions
        end,
    })
end
