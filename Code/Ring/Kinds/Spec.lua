--[[
    Switches to a specialization. It's saved by id, so it means the same spec on every character of
    the class. It's hidden while it's your current spec, and on other classes. The game refuses spec
    changes in combat.
]]

---@class SpecSlice : Slice
---@field id number the specialization id, like 255 for Survival

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Spec = env.AX_Modules:Import("@\\Utils\\Spec")

local SetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.SetSpecialization) or SetSpecialization

---@param specID number
local function Switch(specID)
    if Ring_Kinds.RefuseInCombat() then return end
    local index = Utils_Spec.GetSpecIndex(specID)
    if index and SetSpecialization then SetSpecialization(index) end
end

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Spec,
    versions = { env.GameVersion.Retail },

    validate = function(slice)
        return type(slice.id) == "number", L["Config - Rings - Edit - Error - Spec"]
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetClick(button, suffix, "spec:" .. slice.id, function() Switch(slice.id) end)
    end,

    icon  = function(slice) return select(3, Utils_Spec.GetSpecInfo(slice.id)) end,
    label = function(slice) return (Utils_Spec.GetSpecInfo(slice.id)) end,

    condition = "spec",
    available = function(slice)
        local index = Utils_Spec.GetSpecIndex(slice.id)
        return index ~= nil and index ~= Utils_Spec.GetCurrentSpec()
    end,

    tooltip = function(tooltip, slice)
        local name, description = Utils_Spec.GetSpecInfo(slice.id)
        if not name then return false end
        return Ring_Kinds.SetTooltipText(tooltip, name, description)
    end,

    search = {
        filter = "spec",
        events = { "PLAYER_SPECIALIZATION_CHANGED" },
        -- Every spec of your class. The current one says so (it stays hidden in game until you
        -- switch).
        scan   = function(add)
            local current = Utils_Spec.GetCurrentSpec()
            Utils_Spec.ForEachSpec(function(index, specID)
                local candidate = add({ kind = Ring_Kinds.Kind.Spec, id = specID })
                if candidate and index == current then
                    candidate.note = L["Config - Rings - Search - Note - CurrentSpec"]
                end
            end)
        end,
    },
})
