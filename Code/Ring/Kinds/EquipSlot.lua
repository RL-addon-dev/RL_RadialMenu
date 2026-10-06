--[[
    equipslot   slot: inventory slot (13 = trinket 1): uses whatever is equipped there; hidden while
                that item has no use effect
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

-- Every gear slot except the shirt, in paper doll order. Also the Gear built-in menu (Ring_Auto).
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- GetInventorySlotInfo tokens, for an empty slot's icon.
local SLOT_TOKENS = {
    [1] = "HEADSLOT", [2] = "NECKSLOT", [3] = "SHOULDERSLOT", [5] = "CHESTSLOT", [6] = "WAISTSLOT",
    [7] = "LEGSSLOT", [8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [11] = "FINGER0SLOT",
    [12] = "FINGER1SLOT", [13] = "TRINKET0SLOT", [14] = "TRINKET1SLOT", [15] = "BACKSLOT",
    [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT"
}

local function HasUse(slot)
    local itemID = GetInventoryItemID("player", slot)
    return itemID ~= nil and C_Item.GetItemSpell(itemID) ~= nil
end

Ring_Kinds.Register({
    kind  = "equipslot",
    slots = SLOTS,

    validate = function(slice)
        return type(slice.slot) == "number", "equipped slot needs a slot number (13 = trinket 1)"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetMacroText(button, suffix, "/use " .. slice.slot)
    end,

    icon = function(slice)
        local icon = GetInventoryItemTexture("player", slice.slot)
        if icon then return icon end
        local token = SLOT_TOKENS[slice.slot]
        return token and select(2, GetInventorySlotInfo(token)) or Ring_Kinds.QUESTION_MARK_ICON
    end,
    label = function(slice)
        local slotName = L["Config - Rings - Slot - " .. slice.slot] or format(L["Config - Rings - Slot - Other"], slice.slot)
        local itemID = GetInventoryItemID("player", slice.slot)
        local itemName = itemID and C_Item.GetItemNameByID(itemID)
        return itemName and (slotName .. ": " .. itemName) or slotName
    end,

    cooldown = function(slice) return "inventory", slice.slot end,

    condition = "equipslot",
    available = function(slice) return HasUse(slice.slot) end,

    tooltip = function(tooltip, slice)
        if not GetInventoryItemID("player", slice.slot) then return false end
        tooltip:SetInventoryItem("player", slice.slot)
        return true
    end,

    search = {
        filter = "misc",
        events = { "PLAYER_EQUIPMENT_CHANGED" },
        -- Every slot: a slot slice hides until the item there has a use effect, so a slot can be
        -- added ahead of wearing on-use gear in it. Slots with a use effect sort first; the rest
        -- say why they'd be hidden right now.
        scan   = function(add)
            for _, slot in ipairs(SLOTS) do
                local candidate = add({ kind = "equipslot", slot = slot })
                if candidate and not HasUse(slot) then
                    candidate.group = 1
                    candidate.note = GetInventoryItemID("player", slot)
                        and L["Config - Rings - Search - Note - NoUse"] or L["Config - Rings - Search - Note - Empty"]
                end
            end
        end,
    },
})
