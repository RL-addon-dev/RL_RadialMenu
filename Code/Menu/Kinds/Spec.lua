--[[
    Switches to a specialization. It's saved by id, so it means the same spec on every character of
    the class. It's hidden while it's your current spec, and on other classes. The game refuses spec
    changes in combat.
]]

---@class SpecAction : Action
---@field id number the specialization id, like 255 for Survival

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spec = env.AX_Modules:Import("@\\Utils\\Spec")

local SetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.SetSpecialization) or SetSpecialization

---@param specID number
local function Switch(specID)
    if Menu_Kinds.RefuseInCombat() then return end
    local index = Utils_Spec.GetSpecIndex(specID)
    if index and SetSpecialization then SetSpecialization(index) end
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Spec,
    versions = { env.GameVersion.Retail },

    validate = function(action)
        return type(action.id) == "number", L["Config - Menus - Edit - Error - Spec"]
    end,

    apply = function(button, suffix, action)
        Menu_Kinds.SetClick(button, suffix, "spec:" .. action.id, function() Switch(action.id) end)
    end,

    icon  = function(action) return select(3, Utils_Spec.GetSpecInfo(action.id)) end,
    label = function(action) return (Utils_Spec.GetSpecInfo(action.id)) end,

    condition = "spec",
    available = function(action)
        local index = Utils_Spec.GetSpecIndex(action.id)
        return index ~= nil and index ~= Utils_Spec.GetCurrentSpec()
    end,

    tooltip = function(tooltip, action)
        local name, description = Utils_Spec.GetSpecInfo(action.id)
        if not name then return false end
        return Menu_Kinds.SetTooltipText(tooltip, name, description)
    end,

    search = {
        filter = "spec",
        events = { "PLAYER_SPECIALIZATION_CHANGED" },
        -- Every spec of your class. The current one says so (it stays hidden in game until you
        -- switch).
        scan   = function(add)
            local current = Utils_Spec.GetCurrentSpec()
            Utils_Spec.ForEachSpec(function(index, specID)
                local candidate = add({ kind = Menu_Kinds.Kind.Spec, id = specID })
                if candidate and index == current then
                    candidate.note = L["Config - Menus - Search - Note - CurrentSpec"]
                end
            end)
        end,
    },
})
