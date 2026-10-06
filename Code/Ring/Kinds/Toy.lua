--[[
    toy     id: toy item id
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local IsToy = Ring_Kinds.IsToy

Ring_Kinds.Register({
    kind = "toy",

    validate = function(slice)
        return type(slice.id) == "number", "toy needs a numeric item id"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetAttribute(button, "type", suffix, "toy")
        Ring_Kinds.SetAttribute(button, "toy", suffix, slice.id)
    end,

    icon  = function(slice) return C_Item.GetItemIconByID(slice.id) end,
    label = function(slice) return C_Item.GetItemNameByID(slice.id) or ("toy:" .. slice.id) end,

    cooldown = function(slice) return "item", slice.id end,

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
                    add({ kind = "toy", id = itemID }, name, icon)
                end
            end
        end,
    },

    lookupId = function(id)
        if IsToy(id) then return { kind = "toy", id = id } end
    end,

    cursor = {
        item = function(itemID)
            if IsToy(itemID) then return { kind = "toy", id = itemID } end
        end,
    },
})
