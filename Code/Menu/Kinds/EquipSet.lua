--[[
    Equips an equipment set from the game's Equipment Manager (/equipset). It's saved by name, like
    the macro, and hidden while you're wearing it, and while there's no set of that name.
]]

---@class EquipSetAction : Action
---@field name string the set's name

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.EquipSet,

    validate = function(action)
        return type(action.name) == "string" and action.name ~= "", L["Config - Menus - Edit - Error - EquipSet"]
    end,

    apply = function(button, suffix, action)
        Menu_Kinds.SetMacroText(button, suffix, "/equipset " .. action.name)
    end,

    icon  = function(action) return select(2, Utils_Item.GetEquipmentSetInfo(action.name)) end,
    label = function(action) return action.name end,

    condition = "equipset",
    available = function(action)
        local name, _, _, isEquipped = Utils_Item.GetEquipmentSetInfo(action.name)
        return name ~= nil and not isEquipped
    end,

    tooltip = function(tooltip, action)
        return Menu_Kinds.SetTooltipText(tooltip, action.name, L["Config - Menus - Search - Kind - equipset"])
    end,

    search = {
        filter = "equipment",
        events = { "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" },
        scan   = function(add)
            Utils_Item.ForEachEquipmentSet(function(name, icon, isEquipped)
                local candidate = add({ kind = Menu_Kinds.Kind.EquipSet, name = name }, name, icon)
                if candidate and isEquipped then candidate.note = L["Config - Menus - Search - Note - Wearing"] end
            end)
        end,
    },
})
