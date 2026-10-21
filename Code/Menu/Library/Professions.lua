--[[
    Professions: the spells of your professions (Utils_Spell.GetProfessionSpells). That's each
    profession itself, which opens its window, and its extra spells (Disenchant, Prospecting,
    Survey, Fishing, ...). They're cast by id (the spell kind's `byId`, see GetProfessionSpells).
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

Menu_Data.RegisterLibraryMenu({
    key      = "professions",
    category = Menu_Data.LibraryCategory.Character,
    name     = "Config - Menus - ProfessionMenu - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    events   = { "SKILL_LINES_CHANGED", "SPELLS_CHANGED" },
    scan     = function()
        return Menu_Data.MakeActions(Menu_Kinds.Kind.Spell, Utils_Spell.GetProfessionSpells(), nil, { byId = true })
    end,
})
