--[[
    A battle pet (a companion), summoned or dismissed, or a random favorite pet.
]]

---@class BattlePetSlice : Slice
---@field guid string the pet's GUID ("BattlePet-..."), or "favorite" for a random favorite

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local RANDOM_FAVORITE = "favorite" -- saved data, never renamed
local ICON = "Interface\\Icons\\INV_Pet_BattlePetTraining"

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.BattlePet,

    ---@param slice BattlePetSlice
    validate = function(slice)
        return type(slice.guid) == "string", L["Config - Rings - Edit - Error - BattlePet"]
    end,

    -- Not shared (Data\Share.lua), because a pet's GUID only means something on its owner's
    -- account. A random favorite works anywhere.
    share = {
        ---@param slice BattlePetSlice
        pack = function(slice)
            if slice.guid ~= RANDOM_FAVORITE then return nil, Ring_Data.ShareSkip.BattlePet end
            return { kind = Ring_Kinds.Kind.BattlePet, guid = RANDOM_FAVORITE }
        end,
    },

    -- No secure action type summons companions, and the journal API isn't protected.
    ---@param slice BattlePetSlice
    apply = function(button, suffix, slice)
        if slice.guid == RANDOM_FAVORITE then
            Ring_Kinds.SetMacroText(button, suffix, "/randomfavoritepet")
        else
            Ring_Kinds.SetMacroText(button, suffix, ("/run C_PetJournal.SummonPetByGUID(%q)"):format(slice.guid))
        end
    end,

    ---@param slice BattlePetSlice
    icon = function(slice)
        if slice.guid == RANDOM_FAVORITE then return ICON end
        local speciesID = C_PetJournal.GetPetInfoByPetID(slice.guid)
        local icon = speciesID and select(2, C_PetJournal.GetPetInfoBySpeciesID(speciesID))
        return icon or ICON
    end,
    ---@param slice BattlePetSlice
    label = function(slice)
        if slice.guid == RANDOM_FAVORITE then return L["Config - Rings - Search - RandomPet"] end
        local speciesID, customName = C_PetJournal.GetPetInfoByPetID(slice.guid)
        if customName and customName ~= "" then return customName end
        return (speciesID and C_PetJournal.GetPetInfoBySpeciesID(speciesID)) or L["Config - Rings - Search - Kind - battlepet"]
    end,

    ---@param slice BattlePetSlice
    tooltip = function(tooltip, slice)
        if slice.guid == RANDOM_FAVORITE or not tooltip.SetCompanionPet then return false end
        tooltip:SetCompanionPet(slice.guid)
        return true
    end,

    search = {
        filter = "battlepet",
        events = { "PET_JOURNAL_LIST_UPDATE" },
        scan   = function(add)
            add({ kind = Ring_Kinds.Kind.BattlePet, guid = RANDOM_FAVORITE })

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
                add({ kind = Ring_Kinds.Kind.BattlePet, guid = pet.guid }, pet.name, pet.icon)
            end
        end,
    },

    cursor = {
        -- From the Pet Journal, info1 is the pet's GUID.
        battlepet = function(guid)
            if type(guid) == "string" and guid ~= "" then return { kind = Ring_Kinds.Kind.BattlePet, guid = guid } end
        end,
    },
})
