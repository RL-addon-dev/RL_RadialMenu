--[[
    Loads a saved talent loadout, like picking it in the talent frame (the game then commits it
    with a short cast). It's hidden unless you're in its spec, and while it's your active loadout.
    Loadouts are per character, so on other characters it stays hidden. The game refuses it in
    combat.
]]

---@class LoadoutAction : Action
---@field id number the saved loadout (trait config id)
---@field spec number the spec id it belongs to

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spec = env.AX_Modules:Import("@\\Utils\\Spec")

---@return number?
local function GetCurrentSpecID()
    return select(2, Utils_Spec.GetCurrentSpec())
end

---@param configID number
---@return string?
local function GetLoadoutName(configID)
    local info = C_Traits and C_Traits.GetConfigInfo(configID)
    return (info and info.name ~= "" and info.name) or nil
end

--- The loadout the talent frame shows as selected for spec `specID` (the one you're "in").
---@param specID number
---@return number?
local function GetActiveLoadout(specID)
    return C_ClassTalents.GetLastSelectedSavedConfigID and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
end

---@param configID number
---@param specID number
local function Load(configID, specID)
    if Menu_Kinds.RefuseInCombat() then return end
    if GetCurrentSpecID() ~= specID then return end
    local result = C_ClassTalents.LoadConfig(configID, true)
    if Enum.LoadConfigResult and result == Enum.LoadConfigResult.Error then return end
    -- LoadConfig applies the build, but not which saved loadout the talent frame shows as
    -- selected. The frame does both, so this does too. It's protected and checked, because its
    -- signature has changed before (it once took only the config id), and an error here would end
    -- the click.
    local Update = C_ClassTalents.UpdateLastSelectedSavedConfigID
    if not Update then return end
    pcall(Update, specID, configID)
    if GetActiveLoadout(specID) ~= configID then pcall(Update, configID) end
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Loadout,
    versions = { env.GameVersion.Retail },

    ---@param action LoadoutAction
    validate = function(action)
        return type(action.id) == "number" and type(action.spec) == "number", L["Config - Menus - Edit - Error - Loadout"]
    end,

    ---@param action LoadoutAction
    apply = function(button, suffix, action)
        Menu_Kinds.SetClick(button, suffix, "loadout:" .. action.id, function() Load(action.id, action.spec) end)
    end,

    -- The spec's icon, because loadouts have none of their own.
    ---@param action LoadoutAction
    icon  = function(action) return select(3, Utils_Spec.GetSpecInfo(action.spec)) end,
    label = function(action) return GetLoadoutName(action.id) or L["Config - Menus - Search - Kind - loadout"] end,

    condition = "loadout",
    ---@param action LoadoutAction
    available = function(action)
        return action.spec == GetCurrentSpecID() and GetLoadoutName(action.id) ~= nil
            and GetActiveLoadout(action.spec) ~= action.id
    end,

    ---@param action LoadoutAction
    tooltip = function(tooltip, action)
        local name = GetLoadoutName(action.id)
        if not name then return false end
        tooltip:SetText(name, 1, 1, 1)
        local specName = Utils_Spec.GetSpecInfo(action.spec)
        local specLine = specName and format(L["Config - Menus - Loadout - Tooltip"], specName)
        tooltip:AddLine(specLine or L["Config - Menus - Search - Kind - loadout"])
        return true
    end,

    search = {
        filter = "spec",
        events = { "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" },
        -- Your current spec's loadouts. The active one says so (it's hidden in game while active).
        scan   = function(add)
            local specID = GetCurrentSpecID()
            local configIDs = (specID and C_ClassTalents.GetConfigIDsBySpecID(specID)) or {}
            local active = specID and GetActiveLoadout(specID)
            for _, configID in ipairs(configIDs) do
                local name = GetLoadoutName(configID)
                local candidate = name and add({ kind = Menu_Kinds.Kind.Loadout, id = configID, spec = specID }, name)
                if candidate and configID == active then
                    candidate.note = L["Config - Menus - Search - Note - ActiveLoadout"]
                end
            end
        end,
    },
})
