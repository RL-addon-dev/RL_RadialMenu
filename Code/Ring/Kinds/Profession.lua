--[[
    Professions in Add Action (the Misc filter), meaning your profession spells, added as spell
    actions cast by id (`byId`, see Utils_Spell.GetProfessionSpells). It's search only, so it never
    saves actions of its own kind, and has no apply, icon or label (the spell kind's are used).
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Profession,
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },

    search = {
        filter = "misc",
        events = { "SKILL_LINES_CHANGED", "SPELLS_CHANGED" },
        scan   = function(add)
            for _, spellID in ipairs(Utils_Spell.GetProfessionSpells()) do
                local candidate = add({ kind = Ring_Kinds.Kind.Spell, id = spellID, byId = true })
                if candidate then candidate.kindLabel = L["Config - Rings - Search - Kind - profession"] end
            end
        end,
    },
})
