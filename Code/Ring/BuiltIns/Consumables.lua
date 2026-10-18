--[[
    Consumables: four built-in menus filled from your bags, and one holding them as submenus.

        Potions             potions, and Healthstones
        Flasks & Elixirs    flasks, phials, elixirs
        Food & Drink        food and drink
        Other Consumables   bandages, scrolls, explosives and devices, item enhancements, Vantus
                            runes, and on Retail also the game's Consumable - Other (weapon oils
                            and stones, augment runes, ...) and curios
        Consumables         the four above (scroll submenus, one wedge each, hidden while empty)

    Only items with a use (an item spell) are listed. Healthstones are Consumable - Other too, but
    they're placed by id in Potions. Each item is listed once, sorted by type then item id, so a
    refill doesn't reshuffle them as items move around the bags (the menus remember a custom order
    too).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

local CONSUMABLE_CLASS = (Enum.ItemClass and Enum.ItemClass.Consumable) or 0

-- The four menus' keys (saved data, never renamed).
local MENU = {
    Potions = "potions",
    Flasks  = "flasks",
    Food    = "food",
    Other   = "utility",
}
local MENU_ORDER = { MENU.Potions, MENU.Flasks, MENU.Food, MENU.Other } -- the Consumables menu's order
local MENU_NAMES = {
    [MENU.Potions] = "Config - Rings - PotionsRing - Name",
    [MENU.Flasks]  = "Config - Rings - FlasksRing - Name",
    [MENU.Food]    = "Config - Rings - FoodRing - Name",
    [MENU.Other]   = "Config - Rings - UtilityRing - Name",
}

-- Consumable subclass ids (the same in retail and WoW Forever), by the menu they go in.
local MENU_BY_SUBCLASS = {
    [1] = MENU.Potions, -- Potion
    [2] = MENU.Flasks,  -- Elixir
    [3] = MENU.Flasks,  -- Flasks & Phials
    [5] = MENU.Food,    -- Food & Drink
    [0] = MENU.Other,   -- Explosives & Devices (WoW Forever: generic consumables)
    [4] = MENU.Other,   -- Scroll
    [6] = MENU.Other,   -- Item Enhancement
    [7] = MENU.Other,   -- Bandage
    [9] = MENU.Other,   -- Vantus Rune
}
if env.GAME_VERSION == env.GameVersion.Retail then
    MENU_BY_SUBCLASS[8] = MENU.Other  -- Other, like weapon oils and stones, augment runes, ...
    MENU_BY_SUBCLASS[10] = MENU.Other -- Utility Curio
    MENU_BY_SUBCLASS[11] = MENU.Other -- Combat Curio
end
-- Items placed by id, whatever their subclass. Healthstones are Consumable - Other (8).
local MENU_BY_ITEM = {
    [5512]   = MENU.Potions, -- Healthstone (WoW Forever: Minor Healthstone)
    [224464] = MENU.Potions, -- Demonic Healthstone
}
-- WoW Forever's other ranks (Lesser, Healthstone, Greater, Major), and the Improved Healthstone
-- talent's two versions of each rank (19004-19013).
for _, itemID in ipairs({ 5511, 5509, 5510, 9421 }) do MENU_BY_ITEM[itemID] = MENU.Potions end
for itemID = 19004, 19013 do MENU_BY_ITEM[itemID] = MENU.Potions end

local scanned, scannedAt -- the last scan, and when (GetTime, one value per frame)

--- Your usable consumables by menu key, like { potions = { itemID, ... }, ... }, sorted. It's
--- scanned once per frame, because the four menus refill together (Ring_Auto), each asking for its
--- own part.
---@return table<string, number[]>
local function ScanBags()
    local now = GetTime()
    if scanned and scannedAt == now then return scanned end
    local byMenu, subclassOf, seen = {}, {}, {}
    for _, key in ipairs(MENU_ORDER) do byMenu[key] = {} end
    Utils_Item.ForEachBagItem(function(_, _, itemID)
        if seen[itemID] then return end
        seen[itemID] = true
        local classID, subclassID = select(6, C_Item.GetItemInfoInstant(itemID))
        local key = MENU_BY_ITEM[itemID] or (classID == CONSUMABLE_CLASS and MENU_BY_SUBCLASS[subclassID])
        if key and C_Item.GetItemSpell(itemID) then
            subclassOf[itemID] = subclassID
            table.insert(byMenu[key], itemID)
        end
    end)
    for _, itemIDs in pairs(byMenu) do
        table.sort(itemIDs, function(a, b)
            if subclassOf[a] ~= subclassOf[b] then return subclassOf[a] < subclassOf[b] end
            return a < b
        end)
    end
    scanned, scannedAt = byMenu, now
    return byMenu
end

for _, key in ipairs(MENU_ORDER) do
    Ring_Data.RegisterBuiltIn({
        key      = key,
        category = Ring_Data.LibraryCategory.Consumables,
        name     = MENU_NAMES[key],
        events   = { "BAG_UPDATE_DELAYED" },
        scan     = function() return Ring_Data.MakeSlices(Ring_Kinds.Kind.Item, ScanBags()[key]) end,
    })
end

Ring_Data.RegisterBuiltIn({
    key      = "consumables",
    category = Ring_Data.LibraryCategory.Consumables,
    name     = "Config - Rings - ConsumablesRing - Name",
    -- Always the four menus. Each hides in game while it's empty (submenu visibility).
    scan     = function()
        local ringIDs = {}
        for _, key in ipairs(MENU_ORDER) do
            local ring = Ring_Data.GetBuiltInRing(key)
            if ring then ringIDs[#ringIDs + 1] = ring.id end
        end
        return Ring_Data.MakeSlices(Ring_Kinds.Kind.Ring, ringIDs, "ring")
    end,
})
