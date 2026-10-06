--[[
    zone    (no fields) the current zone ability; hidden while there's none. Its secure attributes
            name the ability, so the menus rebuild when it changes (attributesChangeWith). Icon,
            name, cooldown and tooltip follow what it is right now (Dungeon Assistance turning into
            other spells), like the Zone Ability button; the cast stays on the ability itself.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\Icons\\INV_Misc_Map_01"

local GetZoneAbilitySpell = Ring_Kinds.GetZoneAbilitySpell

--- What the zone ability is right now (its current replacement), or nil.
local function GetShownSpell()
    return select(2, GetZoneAbilitySpell())
end

Ring_Kinds.Register({
    kind = "zone",
    versions = { env.GameVersion.Retail },

    validate = function() return true end,

    apply = function(button, suffix)
        local spellID = GetZoneAbilitySpell()
        if spellID then
            Ring_Kinds.SetSpell(button, suffix, C_Spell.GetSpellName(spellID) or spellID)
        else
            Ring_Kinds.ClearAction(button, suffix)
        end
    end,
    attributesChangeWith = function() return (GetZoneAbilitySpell()) end,

    icon = function()
        local spellID = GetShownSpell()
        return spellID and C_Spell.GetSpellTexture(spellID) or ICON
    end,
    label = function()
        local spellID = GetShownSpell()
        local name = spellID and C_Spell.GetSpellName(spellID)
        return name and format("%s: %s", L["Config - Rings - Special - Zone"], name) or L["Config - Rings - Special - Zone"]
    end,

    cooldown = function()
        local spellID = GetShownSpell()
        if spellID then return "spell", spellID end
    end,

    condition = "zone",
    available = function() return GetZoneAbilitySpell() ~= nil end,

    tooltip = function(tooltip)
        local spellID = GetShownSpell()
        if not spellID then return false end
        tooltip:SetSpellByID(spellID)
        return true
    end,

    search = {
        filter = "misc",
        label  = "special",
        events = { "UPDATE_EXTRA_ACTIONBAR", "ZONE_CHANGED_NEW_AREA" },
        scan   = function(add) add({ kind = "zone" }) end,
    },
})
