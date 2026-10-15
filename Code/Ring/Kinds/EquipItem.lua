--[[
    equipitem   id: item id; slot: equipment slot (1 head .. 19 tabard; 18 ranged / relic on WoW
                Forever); link: that copy's item link (optional). Equips the item from your bags
                into that slot (/equipslot). The link tells copies apart (upgrades, bonuses);
                without it, the first copy of the id. Hidden while none is in your bags. The game
                only swaps weapons in combat. Made by the Equip <Slot> built-in menus
                (BuiltIns\Equipment.lua), which this file also lists in Add Action.
]]

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local IS_RETAIL = env.GAME_VERSION == env.GameVersion.Retail
local MAIN_HAND, OFF_HAND = 16, 17

-- Every slot you can equip into, in paper doll order. WoW Forever has a ranged slot; on retail
-- ranged weapons go in the main hand.
local SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
if not IS_RETAIL then table.insert(SLOTS, 18) end
Ring_Kinds.EQUIP_SLOTS = SLOTS

-- Item equip types -> the slots they go in.
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

-- Equip types that go in any of SLOTS: the bag scan skips everything else (bags, ammo, and the
-- many items with no equip type) before asking for more about it.
local EQUIPPABLE = {}
for _, slot in ipairs(SLOTS) do
    for equipLoc in pairs(SLOT_TYPES[slot]) do EQUIPPABLE[equipLoc] = true end
end

--- Whether your character can use item `id` (its armor or weapon type, class, level): a Mage
--- carrying a shield doesn't see it offered.
local function CanUse(id)
    return not (C_PlayerInfo and C_PlayerInfo.CanUseItem) or C_PlayerInfo.CanUseItem(id)
end

local scanned, scannedAt -- the last scan, and when (GetTime: one value per frame)

--- Usable items in your bags by the slot they go in: [slot] = { { id, link, name }, ... }, once
--- per copy (item link), sorted by name (from the link); every slot of SLOTS has a list.
--- One-handers go in the off hand too for classes that dual wield; rings and trinkets in both of
--- their slots. Equipped items aren't in the bags, so they're never listed. Scanned once per
--- frame: the Equip menus refill together (Ring_Auto), each asking for its own slot. Each bag
--- slot costs an item id and its equip type; only gear asks for its link and whether you can use
--- it.
function Ring_Kinds.GetBagItemsBySlot()
    local now = GetTime()
    if scanned and scannedAt == now then return scanned end
    local bySlot, seen = {}, {}
    for _, slot in ipairs(SLOTS) do bySlot[slot] = {} end
    local dualWield = CanDualWield ~= nil and CanDualWield()
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for bagSlot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, bagSlot)
            local equipLoc = id and select(4, GetItemInfoInstant(id))
            local link = equipLoc and EQUIPPABLE[equipLoc] and C_Container.GetContainerItemLink(bag, bagSlot)
            if link and not seen[link] and CanUse(id) then
                seen[link] = true
                local item = { id = id, link = link, name = link:match("|h%[(.-)%]|h") or "" }
                for _, slot in ipairs(SLOTS) do
                    if SLOT_TYPES[slot][equipLoc] or (slot == OFF_HAND and dualWield and equipLoc == "INVTYPE_WEAPON") then
                        table.insert(bySlot[slot], item)
                    end
                end
            end
        end
    end
    for _, items in pairs(bySlot) do
        table.sort(items, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.link < b.link
        end)
    end
    scanned, scannedAt = bySlot, now
    return bySlot
end

--- How many of item `id` you're wearing (they count in C_Item.GetItemCount, but can't be equipped
--- again).
local function EquippedCount(id)
    local count = 0
    for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        if GetInventoryItemID("player", slot) == id then count = count + 1 end
    end
    return count
end

Ring_Kinds.Register({
    kind = "equipitem",

    validate = function(slice)
        if type(slice.id) ~= "number" then return false, "equip item needs a numeric id" end
        return SLOT_TYPES[slice.slot] ~= nil, "equip item needs an equipment slot"
    end,

    -- The link's item string (item:id:enchant:...: the same copy), not the link itself: its
    -- "[Name]" would read as macro conditions.
    apply = function(button, suffix, slice)
        local item = slice.link and slice.link:match("|H(item:[^|]+)|h") or ("item:" .. slice.id)
        Ring_Kinds.SetMacroText(button, suffix, "/equipslot " .. slice.slot .. " " .. item)
    end,

    icon  = function(slice) return C_Item.GetItemIconByID(slice.id) end,
    label = function(slice) return C_Item.GetItemNameByID(slice.id) or ("item:" .. slice.id) end,

    condition = "equipitem",
    available = function(slice) return C_Item.GetItemCount(slice.id) > EquippedCount(slice.id) end,

    tooltip = function(tooltip, slice)
        if slice.link then tooltip:SetHyperlink(slice.link) else tooltip:SetItemByID(slice.id) end
        tooltip:AddLine(format(L["Config - Rings - EquipItem - EquipsIn"], Ring_Kinds.GetSlotName(slice.slot)), 1, 0.82, 0)
        return true
    end,
})

-- Search only (Ring_Kinds.lua): the equipment built-in menus, as submenus, under the Equipment
-- filter (they're in Menus too, among every other menu).
Ring_Kinds.Register({
    kind = "equipmenus",

    search = {
        filter  = "equipment",
        label   = "ring",
        dynamic = true, -- the menus' ids
        scan    = function(add)
            for _, key in ipairs(Ring_Kinds.EQUIP_MENU_KEYS or {}) do
                local ring = Ring_Data.GetBuiltInRing(key)
                if ring then add({ kind = "ring", ring = ring.id }, ring.name) end
            end
        end,
    },
})
