--[[
    equipset    name: equipment set (the game's Equipment Manager): equips it (/equipset). Stored by
                name, like the macro. Hidden while you're wearing it, and while there's no set of
                that name.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

--- name, icon, setID, isEquipped of the set called `name`, or nil.
local function GetSetInfo(name)
    local setID = C_EquipmentSet.GetEquipmentSetID(name)
    if not setID then return nil end
    local setName, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return setName, icon, setID, isEquipped
end

--- Calls fn(name, icon, isEquipped) for each of your equipment sets, in the game's order.
function Ring_Kinds.ForEachEquipmentSet(fn)
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then fn(name, icon, isEquipped) end
    end
end

Ring_Kinds.Register({
    kind = "equipset",

    validate = function(slice)
        return type(slice.name) == "string" and slice.name ~= "", "equipment set needs a name"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetMacroText(button, suffix, "/equipset " .. slice.name)
    end,

    icon  = function(slice) return select(2, GetSetInfo(slice.name)) or Ring_Kinds.QUESTION_MARK_ICON end,
    label = function(slice) return slice.name end,

    condition = "equipset",
    available = function(slice)
        local name, _, _, isEquipped = GetSetInfo(slice.name)
        return name ~= nil and not isEquipped
    end,

    tooltip = function(tooltip, slice)
        tooltip:SetText(slice.name, 1, 1, 1)
        tooltip:AddLine(L["Config - Rings - Search - Kind - equipset"], nil, nil, nil, true)
        return true
    end,

    search = {
        filter = "equipment",
        events = { "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" },
        scan   = function(add)
            Ring_Kinds.ForEachEquipmentSet(function(name, icon, isEquipped)
                local candidate = add({ kind = "equipset", name = name }, name, icon)
                if candidate and isEquipped then candidate.note = L["Config - Rings - Search - Note - Wearing"] end
            end)
        end,
    },
})
