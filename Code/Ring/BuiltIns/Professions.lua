--[[
    Professions: the spells of your professions (Utils_Spell.GetProfessionSpells). That's each
    profession itself, which opens its window, and its extra spells (Disenchant, Prospecting,
    Survey, Fishing, ...). They're cast by id (the spell kind's `byId`, see GetProfessionSpells).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

Ring_Data.RegisterBuiltIn({
    key      = "professions",
    category = Ring_Data.LibraryCategory.Character,
    name     = "Config - Rings - ProfessionRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    events   = { "SKILL_LINES_CHANGED", "SPELLS_CHANGED" },
    scan     = function()
        return Ring_Data.MakeSlices(Ring_Kinds.Kind.Spell, Utils_Spell.GetProfessionSpells(), nil, { byId = true })
    end,
})
