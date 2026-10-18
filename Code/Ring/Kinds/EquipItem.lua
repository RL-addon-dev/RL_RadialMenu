--[[
    Equips an item from your bags into an equipment slot (/equipslot). The link tells copies apart
    (upgrades, bonuses), and without it the first copy of the id is used. It's hidden while none is
    in your bags. The game only swaps weapons in combat.

    The Equip <Slot> built-in menus (BuiltIns\Equipment.lua) make these, and this file also lists
    those menus in Add Action.
]]

---@class EquipItemSlice : Slice
---@field id number the item id
---@field slot integer the equipment slot, 1 head to 19 tabard (18 ranged or relic on WoW Forever)
---@field link string? that copy's item link

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.EquipItem,

    ---@param slice EquipItemSlice
    validate = function(slice)
        if type(slice.id) ~= "number" then return false, L["Config - Rings - Edit - Error - EquipItem"] end
        return Utils_Item.IsEquipSlot(slice.slot), L["Config - Rings - Edit - Error - EquipItemSlot"]
    end,

    -- The link's item string (item:id:enchant:..., the same copy), not the link itself, because
    -- its "[Name]" would read as macro conditions.
    ---@param slice EquipItemSlice
    apply = function(button, suffix, slice)
        local item = (slice.link and slice.link:match("|H(item:[^|]+)|h")) or ("item:" .. slice.id)
        Ring_Kinds.SetMacroText(button, suffix, "/equipslot " .. slice.slot .. " " .. item)
    end,

    icon  = function(slice) return C_Item.GetItemIconByID(slice.id) end,
    label = function(slice) return C_Item.GetItemNameByID(slice.id) end,

    condition = "equipitem",
    available = function(slice) return C_Item.GetItemCount(slice.id) > Utils_Item.GetEquippedCount(slice.id) end,

    ---@param slice EquipItemSlice
    tooltip = function(tooltip, slice)
        if slice.link then tooltip:SetHyperlink(slice.link) else tooltip:SetItemByID(slice.id) end
        tooltip:AddLine(format(L["Config - Rings - EquipItem - EquipsIn"], Utils_Item.GetSlotName(slice.slot)), 1, 0.82, 0)
        return true
    end,
})

-- Search only (see Ring_Kinds.lua). The equipment built-in menus, as submenus, under the Equipment
-- filter. They're in Menus too, among every other menu.
Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.EquipMenus,

    search = {
        filter  = "equipment",
        label   = "ring",
        dynamic = true, -- the menus' ids
        scan    = function(add)
            for _, key in ipairs(Ring_Data.EQUIP_MENU_KEYS or {}) do
                local ring = Ring_Data.GetBuiltInRing(key)
                if ring then add({ kind = Ring_Kinds.Kind.Ring, ring = ring.id }, ring.name) end
            end
        end,
    },
})
