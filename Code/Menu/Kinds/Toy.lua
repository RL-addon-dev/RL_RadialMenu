--[[
    A toy, from your Toy Box.
]]

---@class ToyAction : Action
---@field id number the toy's item id

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Toy,

    validate = function(action)
        return type(action.id) == "number", L["Config - Menus - Edit - Error - Toy"]
    end,

    apply = function(button, suffix, action)
        Menu_Kinds.SetAction(button, suffix, "toy", action.id)
    end,

    icon  = function(action) return C_Item.GetItemIconByID(action.id) end,
    label = function(action) return C_Item.GetItemNameByID(action.id) end,

    cooldown = function(action) return Menu_Kinds.Source.Item, action.id end,

    tooltip = function(tooltip, action)
        tooltip:SetToyByItemID(action.id)
        return true
    end,

    search = {
        filter = "toy",
        events = { "TOYS_UPDATED", "NEW_TOY_ADDED" },
        -- Follows the Toy Box's own filters (changing them would change the user's Toy Box view).
        scan   = function(add)
            for index = 1, C_ToyBox.GetNumFilteredToys() do
                local itemID = C_ToyBox.GetToyFromIndex(index)
                if itemID and itemID > 0 and PlayerHasToy(itemID) then
                    local _, name, icon = C_ToyBox.GetToyInfo(itemID)
                    add({ kind = Menu_Kinds.Kind.Toy, id = itemID }, name, icon)
                end
            end
        end,
    },

    lookupId = function(id)
        if Utils_Item.IsToy(id) then return { kind = Menu_Kinds.Kind.Toy, id = id } end
    end,

    cursor = {
        item = function(itemID)
            if Utils_Item.IsToy(itemID) then return { kind = Menu_Kinds.Kind.Toy, id = itemID } end
        end,
    },
})
