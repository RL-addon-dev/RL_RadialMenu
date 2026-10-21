--[[
    Items: toys, equipment sets, equipment slots, and the gear in your bags by the slot it goes in.
]]

local env = select(2, ...)
local L = env.L
local Utils_Item = env.AX_Modules:New("@\\Utils\\Item")

local IS_RETAIL = env.GAME_VERSION == env.GameVersion.Retail
local MAIN_HAND, OFF_HAND = 16, 17

-- The last bag to look in. The backpack is bag 0, followed by the equipped bags and the reagent bag.
Utils_Item.LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

--- Calls `callback(bag, slot, itemID)` for every item in your bags, backpack first.
---@param callback fun(bag: integer, slot: integer, itemID: number)
function Utils_Item.ForEachBagItem(callback)
    for bag = 0, Utils_Item.LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then callback(bag, slot, itemID) end
        end
    end
end

--- Whether item `itemID` is a toy you own.
---@param itemID number
---@return boolean
function Utils_Item.IsToy(itemID)
    return PlayerHasToy(itemID) and C_ToyBox.GetToyInfo(itemID) ~= nil
end



-- Equipment sets (the game's Equipment Manager)

--- The equipment set called `name`, or nil when there's none.
---@param name string
---@return string? name
---@return number|string|nil icon
---@return number? setID
---@return boolean? isEquipped
function Utils_Item.GetEquipmentSetInfo(name)
    local setID = C_EquipmentSet.GetEquipmentSetID(name)
    if not setID then return nil end
    local setName, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return setName, icon, setID, isEquipped
end

--- Calls `callback(name, icon, isEquipped)` for each of your equipment sets, in the game's order.
---@param callback fun(name: string, icon: number|string, isEquipped: boolean)
function Utils_Item.ForEachEquipmentSet(callback)
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then callback(name, icon, isEquipped) end
    end
end



-- Equipment slots

-- GetInventorySlotInfo tokens, for an empty slot's icon.
local SLOT_TOKENS = {
    [1] = "HEADSLOT", [2] = "NECKSLOT", [3] = "SHOULDERSLOT", [4] = "SHIRTSLOT", [5] = "CHESTSLOT",
    [6] = "WAISTSLOT", [7] = "LEGSSLOT", [8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT",
    [11] = "FINGER0SLOT", [12] = "FINGER1SLOT", [13] = "TRINKET0SLOT", [14] = "TRINKET1SLOT",
    [15] = "BACKSLOT", [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT", [18] = "RANGEDSLOT",
    [19] = "TABARDSLOT"
}

--- An equipment slot's name, like "Trinket 1".
---@param slot integer an inventory slot
---@return string
function Utils_Item.GetSlotName(slot)
    return L["Config - Menus - Slot - " .. slot] or format(L["Config - Menus - Slot - Other"], slot)
end

--- An empty equipment slot's icon, or nil for a slot the game has no icon for.
---@param slot integer an inventory slot
---@return number|string|nil
function Utils_Item.GetSlotIcon(slot)
    local token = SLOT_TOKENS[slot]
    return token and select(2, GetInventorySlotInfo(token)) or nil
end

-- Every slot you can equip into, in paper doll order. WoW Forever has a ranged slot, and on retail
-- ranged weapons go in the main hand.
local EQUIP_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
if not IS_RETAIL then table.insert(EQUIP_SLOTS, 18) end
Utils_Item.EQUIP_SLOTS = EQUIP_SLOTS

-- Item equip types, by the slots they go in.
local SLOT_TYPES = {
    [1] = { INVTYPE_HEAD = true }, [2] = { INVTYPE_NECK = true }, [3] = { INVTYPE_SHOULDER = true },
    [4] = { INVTYPE_BODY = true }, [5] = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
    [6] = { INVTYPE_WAIST = true }, [7] = { INVTYPE_LEGS = true }, [8] = { INVTYPE_FEET = true },
    [9] = { INVTYPE_WRIST = true }, [10] = { INVTYPE_HAND = true }, [11] = { INVTYPE_FINGER = true },
    [12] = { INVTYPE_FINGER = true }, [13] = { INVTYPE_TRINKET = true }, [14] = { INVTYPE_TRINKET = true },
    [15] = { INVTYPE_CLOAK = true }, [19] = { INVTYPE_TABARD = true },
    [MAIN_HAND] = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true },
    [OFF_HAND] = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true },
    [18] = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
}
if IS_RETAIL then
    SLOT_TYPES[MAIN_HAND].INVTYPE_RANGED, SLOT_TYPES[MAIN_HAND].INVTYPE_RANGEDRIGHT = true, true
end

-- Equip types that go in any of EQUIP_SLOTS. The bag scan skips everything else (bags, ammo, and
-- the many items with no equip type) before asking for more about it.
local EQUIPPABLE = {}
for _, slot in ipairs(EQUIP_SLOTS) do
    for equipLoc in pairs(SLOT_TYPES[slot]) do EQUIPPABLE[equipLoc] = true end
end

--- Whether `slot` is a slot items can be equipped into.
---@param slot any
---@return boolean
function Utils_Item.IsEquipSlot(slot)
    return SLOT_TYPES[slot] ~= nil
end

--- How many of item `id` you're wearing. They count in C_Item.GetItemCount, but can't be equipped
--- again.
---@param id number
---@return integer
function Utils_Item.GetEquippedCount(id)
    local count = 0
    for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        if GetInventoryItemID("player", slot) == id then count = count + 1 end
    end
    return count
end

--- Whether your character can use item `id` (its armor or weapon type, class and level). A Mage
--- carrying a shield doesn't see it offered.
---@param id number
---@return boolean
local function CanUse(id)
    return not (C_PlayerInfo and C_PlayerInfo.CanUseItem) or C_PlayerInfo.CanUseItem(id)
end

---@class BagItem
---@field id number
---@field link string that copy's item link
---@field name string from the link

local scanned, scannedAt -- the last scan, and when (GetTime, one value per frame)

--- The usable items in your bags by the slot they go in, once per copy (item link) and sorted by
--- name. Every slot of EQUIP_SLOTS has a list. One-handers go in the off hand too for classes that
--- dual wield, and menus and trinkets in both of their slots. Equipped items aren't in the bags,
--- so they're never listed.
---
--- Scanned once per frame, because the Equip menus refill together (Menu_Auto), each asking for
--- its own slot. Each bag slot costs an item id and its equip type. Only gear asks for its link and
--- whether you can use it.
---@return table<integer, BagItem[]>
function Utils_Item.GetBagItemsBySlot()
    local now = GetTime()
    if scanned and scannedAt == now then return scanned end
    local bySlot, seen = {}, {}
    for _, slot in ipairs(EQUIP_SLOTS) do bySlot[slot] = {} end
    local dualWield = CanDualWield ~= nil and CanDualWield()
    Utils_Item.ForEachBagItem(function(bag, bagSlot, id)
        local equipLoc = select(4, C_Item.GetItemInfoInstant(id))
        local link = equipLoc and EQUIPPABLE[equipLoc] and C_Container.GetContainerItemLink(bag, bagSlot)
        if not link or seen[link] or not CanUse(id) then return end
        seen[link] = true
        local item = { id = id, link = link, name = link:match("|h%[(.-)%]|h") or "" }
        for _, slot in ipairs(EQUIP_SLOTS) do
            if SLOT_TYPES[slot][equipLoc] or (slot == OFF_HAND and dualWield and equipLoc == "INVTYPE_WEAPON") then
                table.insert(bySlot[slot], item)
            end
        end
    end)
    for _, items in pairs(bySlot) do
        table.sort(items, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.link < b.link
        end)
    end
    scanned, scannedAt = bySlot, now
    return bySlot
end
