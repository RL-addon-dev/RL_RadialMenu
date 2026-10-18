--[[
    An equipped slot (13 = trinket 1). It uses whatever is equipped there, and it's hidden while
    that item has no use effect.
]]

---@class EquipSlotSlice : Slice
---@field slot integer the inventory slot

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

-- Every gear slot except the shirt, in paper doll order. The Gear built-in menu uses it too.
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

--- Whether the item equipped in `slot` has a use effect.
---@param slot integer
---@return boolean
local function HasUse(slot)
    local itemID = GetInventoryItemID("player", slot)
    return itemID ~= nil and C_Item.GetItemSpell(itemID) ~= nil
end

Ring_Kinds.Register({
    kind  = Ring_Kinds.Kind.EquipSlot,
    slots = SLOTS,

    ---@param slice EquipSlotSlice
    validate = function(slice)
        return type(slice.slot) == "number", L["Config - Rings - Edit - Error - EquipSlot"]
    end,

    ---@param slice EquipSlotSlice
    apply = function(button, suffix, slice)
        Ring_Kinds.SetMacroText(button, suffix, "/use " .. slice.slot)
    end,

    ---@param slice EquipSlotSlice
    icon = function(slice)
        return GetInventoryItemTexture("player", slice.slot) or Utils_Item.GetSlotIcon(slice.slot)
    end,
    ---@param slice EquipSlotSlice
    label = function(slice)
        local slotName = Utils_Item.GetSlotName(slice.slot)
        local itemID = GetInventoryItemID("player", slice.slot)
        local itemName = itemID and C_Item.GetItemNameByID(itemID)
        return (itemName and (slotName .. ": " .. itemName)) or slotName
    end,

    ---@param slice EquipSlotSlice
    cooldown = function(slice) return Ring_Kinds.Source.Inventory, slice.slot end,
    ---@param slice EquipSlotSlice
    state    = function(slice) return Ring_Kinds.Source.Inventory, slice.slot end,

    condition = "equipslot",
    ---@param slice EquipSlotSlice
    available = function(slice) return HasUse(slice.slot) end,

    ---@param slice EquipSlotSlice
    tooltip = function(tooltip, slice)
        if not GetInventoryItemID("player", slice.slot) then return false end
        tooltip:SetInventoryItem("player", slice.slot)
        return true
    end,

    search = {
        filter = "misc",
        events = { "PLAYER_EQUIPMENT_CHANGED" },
        -- Every slot. A slot action hides until the item there has a use effect, so a slot can be
        -- added ahead of wearing on-use gear in it. Slots with a use effect sort first, and the
        -- rest say why they'd be hidden right now.
        scan   = function(add)
            for _, slot in ipairs(SLOTS) do
                local candidate = add({ kind = Ring_Kinds.Kind.EquipSlot, slot = slot })
                if candidate and not HasUse(slot) then
                    candidate.group = 1
                    candidate.note = (GetInventoryItemID("player", slot) and L["Config - Rings - Search - Note - NoUse"])
                        or L["Config - Rings - Search - Note - Empty"]
                end
            end
        end,
    },
})
