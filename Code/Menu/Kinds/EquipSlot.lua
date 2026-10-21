--[[
    An equipped slot (13 = trinket 1). It uses whatever is equipped there, and it's hidden while
    that item has no use effect.
]]

---@class EquipSlotAction : Action
---@field slot integer the inventory slot

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

-- Every gear slot except the shirt, in paper doll order. The Gear library menu uses it too.
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
Menu_Kinds.GEAR_SLOTS = SLOTS

--- Whether the item equipped in `slot` has a use effect.
---@param slot integer
---@return boolean
local function HasUse(slot)
    local itemID = GetInventoryItemID("player", slot)
    return itemID ~= nil and C_Item.GetItemSpell(itemID) ~= nil
end

Menu_Kinds.Register({
    kind  = Menu_Kinds.Kind.EquipSlot,

    ---@param action EquipSlotAction
    validate = function(action)
        return type(action.slot) == "number", L["Config - Menus - Edit - Error - EquipSlot"]
    end,

    ---@param action EquipSlotAction
    apply = function(button, suffix, action)
        Menu_Kinds.SetMacroText(button, suffix, "/use " .. action.slot)
    end,

    ---@param action EquipSlotAction
    icon = function(action)
        return GetInventoryItemTexture("player", action.slot) or Utils_Item.GetSlotIcon(action.slot)
    end,
    ---@param action EquipSlotAction
    label = function(action)
        local slotName = Utils_Item.GetSlotName(action.slot)
        local itemID = GetInventoryItemID("player", action.slot)
        local itemName = itemID and C_Item.GetItemNameByID(itemID)
        return (itemName and (slotName .. ": " .. itemName)) or slotName
    end,

    ---@param action EquipSlotAction
    cooldown = function(action) return Menu_Kinds.Source.Inventory, action.slot end,
    ---@param action EquipSlotAction
    state    = function(action) return Menu_Kinds.Source.Inventory, action.slot end,

    condition = "equipslot",
    ---@param action EquipSlotAction
    available = function(action) return HasUse(action.slot) end,

    ---@param action EquipSlotAction
    tooltip = function(tooltip, action)
        if not GetInventoryItemID("player", action.slot) then return false end
        tooltip:SetInventoryItem("player", action.slot)
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
                local candidate = add({ kind = Menu_Kinds.Kind.EquipSlot, slot = slot })
                if candidate and not HasUse(slot) then
                    candidate.group = 1
                    candidate.note = (GetInventoryItemID("player", slot) and L["Config - Menus - Search - Note - NoUse"])
                        or L["Config - Menus - Search - Note - Empty"]
                end
            end
        end,
    },
})
