--[[
    Professions: the spells of your professions (Ring_Kinds.GetProfessionSpells): each profession
    itself (opens its window) and its extra spells (Disenchant, Prospecting, Survey, Fishing, ...).
    Cast by id (spell `byId`), see GetProfessionSpells.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key      = "professions",
    name     = "Config - Rings - ProfessionRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    events   = { "SKILL_LINES_CHANGED", "SPELLS_CHANGED" },
    scan     = function()
        local slices = {}
        for i, spellID in ipairs(Ring_Kinds.GetProfessionSpells()) do
            slices[i] = { kind = "spell", id = spellID, byId = true }
        end
        return slices
    end,
})
