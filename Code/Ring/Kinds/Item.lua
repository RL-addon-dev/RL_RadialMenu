--[[
    item    id: item id; hidden while you have none (toys are their own kind, Toy.lua)
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local IsToy = Ring_Kinds.IsToy

Ring_Kinds.Register({
    kind = "item",

    validate = function(slice)
        return type(slice.id) == "number", "item needs a numeric id"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetAttribute(button, "type", suffix, "item")
        Ring_Kinds.SetAttribute(button, "item", suffix, "item:" .. slice.id)
    end,

    icon  = function(slice) return C_Item.GetItemIconByID(slice.id) end,
    label = function(slice) return C_Item.GetItemNameByID(slice.id) or ("item:" .. slice.id) end,

    cooldown = function(slice) return "item", slice.id end,

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
                        add({ kind = "item", id = itemID }, info.itemName or C_Item.GetItemNameByID(itemID), info.iconFileID)
                    end
                end
            end
        end,
    },

    lookupId = function(id)
        if IsToy(id) or not C_Item.GetItemInfoInstant(id) then return nil end
        return { kind = "item", id = id }, C_Item.GetItemCount(id) == 0 and L["Config - Rings - Search - Note - NoneInBags"] or nil
    end,

    cursor = {
        item = function(itemID)
            if not IsToy(itemID) then return { kind = "item", id = itemID } end
        end,
    },
})
