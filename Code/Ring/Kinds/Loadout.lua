--[[
    loadout id: saved talent loadout (trait config id), spec: the spec id it belongs to. Loads it,
            like picking it in the talent frame (the game then commits it with a short cast).
            Hidden unless you're in its spec, and while it's your active loadout. Loadouts are
            per character: on other characters it stays hidden. The game refuses it in combat.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local function GetCurrentSpecID()
    return select(2, Ring_Kinds.GetCurrentSpec())
end

local function GetLoadoutName(configID)
    local info = C_Traits and C_Traits.GetConfigInfo(configID)
    return info and info.name ~= "" and info.name or nil
end

--- The loadout the talent frame shows as selected for spec `specID` (the one you're "in").
local function GetActiveLoadout(specID)
    return C_ClassTalents.GetLastSelectedSavedConfigID and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
end

local function Load(configID, specID)
    if InCombatLockdown() then
        env.Print(ERR_NOT_IN_COMBAT or "not in combat")
        return
    end
    if GetCurrentSpecID() ~= specID then return end
    local result = C_ClassTalents.LoadConfig(configID, true)
    if Enum.LoadConfigResult and result == Enum.LoadConfigResult.Error then return end
    -- LoadConfig applies the build, not which saved loadout the talent frame shows as selected:
    -- the frame does both, so this does too. Protected and checked: its signature has changed
    -- before (it once took only the config id), and an error here would end the click.
    local Update = C_ClassTalents.UpdateLastSelectedSavedConfigID
    if not Update then return end
    pcall(Update, specID, configID)
    if GetActiveLoadout(specID) ~= configID then pcall(Update, configID) end
end

Ring_Kinds.Register({
    kind = "loadout",
    versions = { env.GameVersion.Retail },

    validate = function(slice)
        return type(slice.id) == "number" and type(slice.spec) == "number", "talent loadout needs a config id and a spec id"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetClick(button, suffix, "loadout:" .. slice.id, function() Load(slice.id, slice.spec) end)
    end,

    -- The spec's icon: loadouts have none of their own.
    icon  = function(slice)
        return select(3, Ring_Kinds.GetSpecInfo(slice.spec)) or Ring_Kinds.QUESTION_MARK_ICON
    end,
    label = function(slice) return GetLoadoutName(slice.id) or L["Config - Rings - Search - Kind - loadout"] end,

    condition = "loadout",
    available = function(slice)
        return slice.spec == GetCurrentSpecID() and GetLoadoutName(slice.id) ~= nil
            and GetActiveLoadout(slice.spec) ~= slice.id
    end,

    tooltip = function(tooltip, slice)
        local name = GetLoadoutName(slice.id)
        if not name then return false end
        tooltip:SetText(name, 1, 1, 1)
        local specName = Ring_Kinds.GetSpecInfo(slice.spec)
        tooltip:AddLine(specName and format(L["Config - Rings - Loadout - Tooltip"], specName) or L["Config - Rings - Search - Kind - loadout"])
        return true
    end,

    search = {
        filter = "spec",
        events = { "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" },
        -- Your current spec's loadouts; the active one says so (hidden in game while active).
        scan   = function(add)
            local specID = GetCurrentSpecID()
            local configIDs = specID and C_ClassTalents.GetConfigIDsBySpecID(specID) or {}
            local active = specID and GetActiveLoadout(specID)
            for _, configID in ipairs(configIDs) do
                local name = GetLoadoutName(configID)
                local candidate = name and add({ kind = "loadout", id = configID, spec = specID }, name)
                if candidate and configID == active then
                    candidate.note = L["Config - Rings - Search - Note - ActiveLoadout"]
                end
            end
        end,
    },
})
