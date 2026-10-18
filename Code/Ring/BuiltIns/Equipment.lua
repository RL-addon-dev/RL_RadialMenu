--[[
    Equip <Slot>: a built-in menu per equipment slot (Equip Head .. Equip Off Hand; Equip Ranged
    on WoW Forever): the items in your bags you can use there. Listed in Add Action under
    Equipment with Equipment Sets (EquipmentSets.lua), to add as submenus: they scroll, or spread
    with a double-click.

    Slot menus list what's in your bags, once per copy (item link), so what you're wearing isn't
    there. They refill together from one bag scan (Utils_Item.GetBagItemsBySlot) as bags, gear
    and your level change.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

-- Slot -> the built-in menu's key (saved: never rename) and name.
local SLOT_KEYS = {
    [1] = "equiphead", [2] = "equipneck", [3] = "equipshoulder", [4] = "equipshirt", [5] = "equipchest",
    [6] = "equipwaist", [7] = "equiplegs", [8] = "equipfeet", [9] = "equipwrist", [10] = "equiphands",
    [11] = "equipring1", [12] = "equipring2", [13] = "equiptrinket1", [14] = "equiptrinket2",
    [15] = "equipback", [16] = "equipmainhand", [17] = "equipoffhand", [18] = "equipranged",
    [19] = "equiptabard",
}

-- The menus Add Action lists under Equipment, in this order (EquipItem.lua): Equipment Sets
-- (EquipmentSets.lua), then the slots.
Ring_Kinds.EQUIP_MENU_KEYS = { "equipsets" }

for _, slot in ipairs(Utils_Item.EQUIP_SLOTS) do
    local key = SLOT_KEYS[slot]
    table.insert(Ring_Kinds.EQUIP_MENU_KEYS, key)
    Ring_Data.RegisterBuiltIn({
        key    = key,
        category = Ring_Data.LibraryCategory.Equipment,
        name   = "Config - Rings - EquipRing - " .. slot,
        events = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" },
        scan   = function()
            local slices = {}
            for _, item in ipairs(Utils_Item.GetBagItemsBySlot()[slot]) do
                slices[#slices + 1] = { kind = Ring_Kinds.Kind.EquipItem, id = item.id, slot = slot, link = item.link }
            end
            return slices
        end,
    })
end
