--[[
    Professions in Add Action (Misc filter): your profession spells, added as spell actions cast by
    id (`byId`, see Ring_Kinds.GetProfessionSpells). Search only: it saves no actions of its own
    kind, so it has no apply, icon or label of its own (the spell kind's are used).
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Kinds.Register({
    kind = "profession",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },

    search = {
        filter = "misc",
        events = { "SKILL_LINES_CHANGED", "SPELLS_CHANGED" },
        scan   = function(add)
            for _, spellID in ipairs(Ring_Kinds.GetProfessionSpells()) do
                local candidate = add({ kind = "spell", id = spellID, byId = true })
                if candidate then candidate.kindLabel = L["Config - Rings - Search - Kind - profession"] end
            end
        end,
    },
})
