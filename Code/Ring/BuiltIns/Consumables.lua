--[[
    Consumables: four built-in menus filled from your bags, and a fifth holding them as submenus.

        Potions             potions
        Flasks & Elixirs    flasks, phials, elixirs
        Food & Drink        food and drink
        Other Consumables   bandages, scrolls, explosives & devices, item enhancements, Vantus runes
        Consumables         the four above (scroll submenus: one wedge each, hidden while empty)

    Only items with a use (an item spell): curios go into a slot, and "Other" is mostly things you
    can't use, so neither is listed. Each item once, sorted by type then item id, so a refill
    doesn't reshuffle them as items move around the bags (the menus remember a custom order too).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")

local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local CONSUMABLE_CLASS = (Enum.ItemClass and Enum.ItemClass.Consumable) or 0

-- Consumable subclass ids (the same in retail and WoW Forever) -> the menu they go in.
local MENU_BY_SUBCLASS = {
    [1] = "potions",   -- Potion
    [2] = "flasks",    -- Elixir
    [3] = "flasks",    -- Flasks & Phials
    [5] = "food",      -- Food & Drink
    [0] = "utility",   -- Explosives & Devices (WoW Forever: generic consumables)
    [4] = "utility",   -- Scroll
    [6] = "utility",   -- Item Enhancement
    [7] = "utility",   -- Bandage
    [9] = "utility",   -- Vantus Rune
}
local CATEGORIES = { "potions", "flasks", "food", "utility" } -- the Consumables menu's order

local scanned, scannedAt -- the last scan, and when (GetTime: one value per frame)

--- Your usable consumables by menu key: { potions = { itemID, ... }, ... }, sorted. Scanned once
--- per frame: the four menus refill together (Ring_Auto), each asking for its own part.
local function ScanBags()
    local now = GetTime()
    if scanned and scannedAt == now then return scanned end
    local byMenu, subclassOf, seen = {}, {}, {}
    for _, key in ipairs(CATEGORIES) do byMenu[key] = {} end
    for bag = 0, LAST_BAG do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local itemID = GetContainerItemID(bag, slot)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                local classID, subclassID = select(6, GetItemInfoInstant(itemID))
                local key = classID == CONSUMABLE_CLASS and MENU_BY_SUBCLASS[subclassID]
                if key and GetItemSpell(itemID) then
                    subclassOf[itemID] = subclassID
                    table.insert(byMenu[key], itemID)
                end
            end
        end
    end
    for _, itemIDs in pairs(byMenu) do
        table.sort(itemIDs, function(a, b)
            if subclassOf[a] ~= subclassOf[b] then return subclassOf[a] < subclassOf[b] end
            return a < b
        end)
    end
    scanned, scannedAt = byMenu, now
    return byMenu
end

local CATEGORY_NAMES = {
    potions = "Config - Rings - PotionsRing - Name",
    flasks  = "Config - Rings - FlasksRing - Name",
    food    = "Config - Rings - FoodRing - Name",
    utility = "Config - Rings - UtilityRing - Name",
}

for _, key in ipairs(CATEGORIES) do
    Ring_Data.RegisterBuiltIn({
        key    = key,
        name   = CATEGORY_NAMES[key],
        events = { "BAG_UPDATE_DELAYED" },
        scan   = function()
            local slices = {}
            for i, itemID in ipairs(ScanBags()[key]) do slices[i] = { kind = "item", id = itemID } end
            return slices
        end,
    })
end

Ring_Data.RegisterBuiltIn({
    key    = "consumables",
    name   = "Config - Rings - ConsumablesRing - Name",
    -- Always the four menus; each hides in game while it's empty (submenu visibility).
    scan   = function()
        local slices = {}
        for _, key in ipairs(CATEGORIES) do
            local ring = Ring_Data.GetBuiltInRing(key)
            if ring then slices[#slices + 1] = { kind = "ring", ring = ring.id } end
        end
        return slices
    end,
})
