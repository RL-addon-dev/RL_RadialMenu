--[[
    spec    id: specialization id (e.g. 255 = Survival): switches to it. Stored by id, so it means
            the same spec on every character of the class; hidden while it's your current spec, and
            on other classes. The game refuses spec changes in combat.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local SetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.SetSpecialization) or SetSpecialization
local GetSpecIndex, GetSpecInfo = Ring_Kinds.GetSpecIndex, Ring_Kinds.GetSpecInfo

local function Switch(specID)
    if InCombatLockdown() then
        env.Print(ERR_NOT_IN_COMBAT or "not in combat")
        return
    end
    local index = GetSpecIndex(specID)
    if index and SetSpecialization then SetSpecialization(index) end
end

Ring_Kinds.Register({
    kind = "spec",
    versions = { env.GameVersion.Retail },

    validate = function(slice)
        return type(slice.id) == "number", "specialization needs a numeric spec id"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetClick(button, suffix, "spec:" .. slice.id, function() Switch(slice.id) end)
    end,

    icon  = function(slice) return select(3, GetSpecInfo(slice.id)) or Ring_Kinds.QUESTION_MARK_ICON end,
    label = function(slice) return GetSpecInfo(slice.id) or ("spec:" .. slice.id) end,

    condition = "spec",
    available = function(slice)
        local index = GetSpecIndex(slice.id)
        return index ~= nil and index ~= Ring_Kinds.GetCurrentSpec()
    end,

    tooltip = function(tooltip, slice)
        local name, description = GetSpecInfo(slice.id)
        if not name then return false end
        tooltip:SetText(name, 1, 1, 1)
        if description then tooltip:AddLine(description, nil, nil, nil, true) end
        return true
    end,

    search = {
        filter = "spec",
        events = { "PLAYER_SPECIALIZATION_CHANGED" },
        -- Every spec of your class; the current one says so (it stays hidden in game until you switch).
        scan   = function(add)
            local current = Ring_Kinds.GetCurrentSpec()
            Ring_Kinds.ForEachSpec(function(index, specID)
                local candidate = add({ kind = "spec", id = specID })
                if candidate and index == current then
                    candidate.note = L["Config - Rings - Search - Note - CurrentSpec"]
                end
            end)
        end,
    },
})

