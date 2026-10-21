--[[
    An item, used from your bags. It's hidden while you have none. Toys are their own kind (Toy.lua).
]]

---@class ItemAction : Action
---@field id number the item id

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Item,

    validate = function(action)
        return type(action.id) == "number", L["Config - Menus - Edit - Error - Item"]
    end,

    apply = function(button, suffix, action)
        Menu_Kinds.SetAction(button, suffix, "item", "item:" .. action.id)
    end,

    icon  = function(action) return C_Item.GetItemIconByID(action.id) end,
    label = function(action) return C_Item.GetItemNameByID(action.id) end,

    cooldown = function(action) return Menu_Kinds.Source.Item, action.id end,
    state    = function(action) return Menu_Kinds.Source.Item, action.id end,

    condition = "item",
    available = function(action) return C_Item.GetItemCount(action.id) > 0 end,

    tooltip = function(tooltip, action)
        tooltip:SetItemByID(action.id)
        return true
    end,

    search = {
        filter = "item",
        events = { "BAG_UPDATE_DELAYED" },
        -- Usable items in the bags, once each.
        scan   = function(add)
            local seen = {}
            Utils_Item.ForEachBagItem(function(bag, slot, itemID)
                if seen[itemID] or not C_Item.GetItemSpell(itemID) or C_ToyBox.GetToyInfo(itemID) then return end
                seen[itemID] = true
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local name = (info and info.itemName) or C_Item.GetItemNameByID(itemID)
                add({ kind = Menu_Kinds.Kind.Item, id = itemID }, name, info and info.iconFileID)
            end)
        end,
    },

    lookupId = function(id)
        if Utils_Item.IsToy(id) or not C_Item.GetItemInfoInstant(id) then return nil end
        local note = (C_Item.GetItemCount(id) == 0 and L["Config - Menus - Search - Note - NoneInBags"]) or nil
        return { kind = Menu_Kinds.Kind.Item, id = id }, note
    end,

    cursor = {
        item = function(itemID)
            if not Utils_Item.IsToy(itemID) then return { kind = Menu_Kinds.Kind.Item, id = itemID } end
        end,
    },
})
