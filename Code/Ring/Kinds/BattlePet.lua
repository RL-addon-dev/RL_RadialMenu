--[[
    battlepet   guid: battle pet GUID ("BattlePet-..."), or "favorite" for a random favorite pet
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local RANDOM_FAVORITE = "favorite"
local ICON = "Interface\\Icons\\INV_Pet_BattlePetTraining"

Ring_Kinds.Register({
    kind = "battlepet",

    validate = function(slice)
        return type(slice.guid) == "string", "battle pet needs a pet GUID (or \"favorite\")"
    end,

    apply = function(button, suffix, slice)
        -- No secure action type summons companions; the journal API isn't protected.
        if slice.guid == RANDOM_FAVORITE then
            Ring_Kinds.SetMacroText(button, suffix, "/randomfavoritepet")
        else
            Ring_Kinds.SetMacroText(button, suffix, ("/run C_PetJournal.SummonPetByGUID(%q)"):format(slice.guid))
        end
    end,

    icon = function(slice)
        if slice.guid == RANDOM_FAVORITE then return ICON end
        local speciesID = C_PetJournal.GetPetInfoByPetID(slice.guid)
        local icon = speciesID and select(2, C_PetJournal.GetPetInfoBySpeciesID(speciesID))
        return icon or ICON
    end,
    label = function(slice)
        if slice.guid == RANDOM_FAVORITE then return L["Config - Rings - Search - RandomPet"] end
        local speciesID, customName = C_PetJournal.GetPetInfoByPetID(slice.guid)
        if customName and customName ~= "" then return customName end
        return speciesID and C_PetJournal.GetPetInfoBySpeciesID(speciesID) or L["Config - Rings - Search - Kind - battlepet"]
    end,

    tooltip = function(tooltip, slice)
        if slice.guid == RANDOM_FAVORITE or not tooltip.SetCompanionPet then return false end
        tooltip:SetCompanionPet(slice.guid)
        return true
    end,

    search = {
        filter = "battlepet",
        events = { "PET_JOURNAL_LIST_UPDATE" },
        scan   = function(add)
            add({ kind = "battlepet", guid = RANDOM_FAVORITE })

            -- One entry per species (you rarely want a specific copy), preferring a favorite, then
            -- a renamed pet. Follows the Pet Journal's own filters, like toys.
            local bySpecies, order = {}, {}
            for index = 1, C_PetJournal.GetNumPets() do
                local petID, speciesID, owned, customName, _, favorite, isRevoked, speciesName, icon = C_PetJournal.GetPetInfoByIndex(index)
                if petID and owned and not isRevoked and speciesID then
                    local current = bySpecies[speciesID]
                    if not current or (favorite and not current.favorite) then
                        if not current then order[#order + 1] = speciesID end
                        local name = (customName and customName ~= "") and customName or speciesName
                        bySpecies[speciesID] = { guid = petID, name = name, icon = icon, favorite = favorite }
                    end
                end
            end
            for _, speciesID in ipairs(order) do
                local pet = bySpecies[speciesID]
                add({ kind = "battlepet", guid = pet.guid }, pet.name, pet.icon)
            end
        end,
    },

    cursor = {
        -- info1 = pet GUID (from the Pet Journal)
        battlepet = function(guid)
            if type(guid) == "string" and guid ~= "" then return { kind = "battlepet", guid = guid } end
        end,
    },
})
