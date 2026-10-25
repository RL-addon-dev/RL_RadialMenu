--[[
    A battle pet (a companion), summoned or dismissed, or a random favorite pet.
]]

---@class BattlePetAction : Action
---@field guid string the pet's GUID ("BattlePet-..."), or "favorite" for a random favorite

local env = select(2, ...)
local L = env.L
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

local RANDOM_FAVORITE = "favorite" -- saved data, never renamed
local ICON = "Interface\\Icons\\INV_Pet_BattlePetTraining"

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.BattlePet,

    ---@param action BattlePetAction
    validate = function(action)
        return type(action.guid) == "string", L["Config - Menus - Edit - Error - BattlePet"]
    end,

    -- Not shared (Data\Share.lua), because a pet's GUID only means something on its owner's
    -- account. A random favorite works anywhere.
    share = {
        ---@param action BattlePetAction
        pack = function(action)
            if action.guid ~= RANDOM_FAVORITE then return nil, Menu_Data.ShareSkip.BattlePet end
            return { kind = Menu_Kinds.Kind.BattlePet, guid = RANDOM_FAVORITE }
        end,
    },

    -- No secure action type summons companions, and the journal API isn't protected.
    ---@param action BattlePetAction
    apply = function(button, suffix, action)
        if action.guid == RANDOM_FAVORITE then
            Menu_Kinds.SetMacroText(button, suffix, "/randomfavoritepet")
        else
            Menu_Kinds.SetMacroText(button, suffix, ("/run C_PetJournal.SummonPetByGUID(%q)"):format(action.guid))
        end
    end,

    ---@param action BattlePetAction
    icon = function(action)
        if action.guid == RANDOM_FAVORITE then return ICON end
        local speciesID = C_PetJournal.GetPetInfoByPetID(action.guid)
        local icon = speciesID and select(2, C_PetJournal.GetPetInfoBySpeciesID(speciesID))
        return icon or ICON
    end,
    ---@param action BattlePetAction
    label = function(action)
        if action.guid == RANDOM_FAVORITE then return L["Config - Menus - Search - RandomPet"] end
        local speciesID, customName = C_PetJournal.GetPetInfoByPetID(action.guid)
        if customName and customName ~= "" then return customName end
        return (speciesID and C_PetJournal.GetPetInfoBySpeciesID(speciesID)) or L["Config - Menus - Search - Kind - battlepet"]
    end,

    ---@param action BattlePetAction
    tooltip = function(tooltip, action)
        if action.guid == RANDOM_FAVORITE or not tooltip.SetCompanionPet then return false end
        tooltip:SetCompanionPet(action.guid)
        return true
    end,

    search = {
        filter = "battlepet",
        events = { "PET_JOURNAL_LIST_UPDATE" },
        scan   = function(add)
            add({ kind = Menu_Kinds.Kind.BattlePet, guid = RANDOM_FAVORITE })

            -- One entry per species (you rarely want a specific copy), preferring a favorite, then
            -- a renamed pet. It follows the Pet Journal's own filters, like toys.
            local bySpecies, order = {}, {}
            for index = 1, C_PetJournal.GetNumPets() do
                local petID, speciesID, owned, customName, _, favorite, isRevoked, speciesName, icon = C_PetJournal.GetPetInfoByIndex(index)
                if petID and owned and not isRevoked and speciesID then
                    local current = bySpecies[speciesID]
                    if not current or (favorite and not current.favorite) then
                        if not current then order[#order + 1] = speciesID end
                        local name = ((customName and customName ~= "") and customName) or speciesName
                        bySpecies[speciesID] = { guid = petID, name = name, icon = icon, favorite = favorite }
                    end
                end
            end
            for _, speciesID in ipairs(order) do
                local pet = bySpecies[speciesID]
                add({ kind = Menu_Kinds.Kind.BattlePet, guid = pet.guid }, pet.name, pet.icon)
            end
        end,
    },

    cursor = {
        -- From the Pet Journal, info1 is the pet's GUID.
        battlepet = function(guid)
            if type(guid) == "string" and guid ~= "" then return { kind = Menu_Kinds.Kind.BattlePet, guid = guid } end
        end,
    },
})
