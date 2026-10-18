--[[
    Equips an equipment set from the game's Equipment Manager (/equipset). It's saved by name, like
    the macro, and hidden while you're wearing it, and while there's no set of that name.
]]

---@class EquipSetSlice : Slice
---@field name string the set's name

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.EquipSet,

    validate = function(slice)
        return type(slice.name) == "string" and slice.name ~= "", L["Config - Rings - Edit - Error - EquipSet"]
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetMacroText(button, suffix, "/equipset " .. slice.name)
    end,

    icon  = function(slice) return select(2, Utils_Item.GetEquipmentSetInfo(slice.name)) end,
    label = function(slice) return slice.name end,

    condition = "equipset",
    available = function(slice)
        local name, _, _, isEquipped = Utils_Item.GetEquipmentSetInfo(slice.name)
        return name ~= nil and not isEquipped
    end,

    tooltip = function(tooltip, slice)
        return Ring_Kinds.SetTooltipText(tooltip, slice.name, L["Config - Rings - Search - Kind - equipset"])
    end,

    search = {
        filter = "equipment",
        events = { "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" },
        scan   = function(add)
            Utils_Item.ForEachEquipmentSet(function(name, icon, isEquipped)
                local candidate = add({ kind = Ring_Kinds.Kind.EquipSet, name = name }, name, icon)
                if candidate and isEquipped then candidate.note = L["Config - Rings - Search - Note - Wearing"] end
            end)
        end,
    },
})
