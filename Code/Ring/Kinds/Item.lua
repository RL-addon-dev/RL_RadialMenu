--[[
    An item, used from your bags. It's hidden while you have none. Toys are their own kind (Toy.lua).
]]

---@class ItemSlice : Slice
---@field id number the item id

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Item,

    validate = function(slice)
        return type(slice.id) == "number", L["Config - Rings - Edit - Error - Item"]
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetAction(button, suffix, "item", "item:" .. slice.id)
    end,

    icon  = function(slice) return C_Item.GetItemIconByID(slice.id) end,
    label = function(slice) return C_Item.GetItemNameByID(slice.id) end,

    cooldown = function(slice) return Ring_Kinds.Source.Item, slice.id end,
    state    = function(slice) return Ring_Kinds.Source.Item, slice.id end,

    condition = "item",
    available = function(slice) return C_Item.GetItemCount(slice.id) > 0 end,

    tooltip = function(tooltip, slice)
        tooltip:SetItemByID(slice.id)
        return true
    end,

    search = {
        filter = "item",
        events = { "BAG_UPDATE_DELAYED" },
        -- Usable items in the bags, once each.
        scan   = function(add)
            local seen = {}
            for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    local itemID = info and info.itemID
                    if itemID and not seen[itemID] and C_Item.GetItemSpell(itemID) and not C_ToyBox.GetToyInfo(itemID) then
                        seen[itemID] = true
                        local name = info.itemName or C_Item.GetItemNameByID(itemID)
                        add({ kind = Ring_Kinds.Kind.Item, id = itemID }, name, info.iconFileID)
                    end
                end
            end
        end,
    },

    lookupId = function(id)
        if Utils_Item.IsToy(id) or not C_Item.GetItemInfoInstant(id) then return nil end
        local note = (C_Item.GetItemCount(id) == 0 and L["Config - Rings - Search - Note - NoneInBags"]) or nil
        return { kind = Ring_Kinds.Kind.Item, id = id }, note
    end,

    cursor = {
        item = function(itemID)
            if not Utils_Item.IsToy(itemID) then return { kind = Ring_Kinds.Kind.Item, id = itemID } end
        end,
    },
})
