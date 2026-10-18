--[[
    A toy, from your Toy Box.
]]

---@class ToySlice : Slice
---@field id number the toy's item id

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Toy,

    validate = function(slice)
        return type(slice.id) == "number", L["Config - Rings - Edit - Error - Toy"]
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetAction(button, suffix, "toy", slice.id)
    end,

    icon  = function(slice) return C_Item.GetItemIconByID(slice.id) end,
    label = function(slice) return C_Item.GetItemNameByID(slice.id) end,

    cooldown = function(slice) return Ring_Kinds.Source.Item, slice.id end,

    tooltip = function(tooltip, slice)
        tooltip:SetToyByItemID(slice.id)
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
                    add({ kind = Ring_Kinds.Kind.Toy, id = itemID }, name, icon)
                end
            end
        end,
    },

    lookupId = function(id)
        if Utils_Item.IsToy(id) then return { kind = Ring_Kinds.Kind.Toy, id = id } end
    end,

    cursor = {
        item = function(itemID)
            if Utils_Item.IsToy(itemID) then return { kind = Ring_Kinds.Kind.Toy, id = itemID } end
        end,
    },
})
