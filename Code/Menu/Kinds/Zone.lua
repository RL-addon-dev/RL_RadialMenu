--[[
    The current zone ability. It has no fields of its own, and it's hidden while there's none. Its
    secure attributes name the ability, so the menus rebuild when it changes (attributesChangeWith).
    Its icon, name, cooldown and tooltip follow what it is right now (Dungeon Assistance turning
    into other spells), like the Zone Ability button, while the cast stays on the ability itself.
]]

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

local ICON = "Interface\\Icons\\INV_Misc_Map_01"

--- What the zone ability is right now (its current replacement), or nil.
---@return number?
local function GetShownSpell()
    return select(2, Utils_Spell.GetZoneAbilitySpell())
end

--- The ability shown right now, which its cooldown and state follow.
---@return string? source Menu_Kinds.Source.Spell
---@return number? spellID
local function ShownSpellSource()
    local spellID = GetShownSpell()
    if spellID then return Menu_Kinds.Source.Spell, spellID end
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Zone,
    versions = { env.GameVersion.Retail },

    apply = function(button, suffix)
        local spellID = Utils_Spell.GetZoneAbilitySpell()
        if spellID then
            Menu_Kinds.SetSpell(button, suffix, C_Spell.GetSpellName(spellID) or spellID)
        else
            Menu_Kinds.ClearAction(button, suffix)
        end
    end,
    attributesChangeWith = function() return (Utils_Spell.GetZoneAbilitySpell()) end,

    icon = function()
        local spellID = GetShownSpell()
        return (spellID and C_Spell.GetSpellTexture(spellID)) or ICON
    end,
    label = function()
        local spellID = GetShownSpell()
        local name = spellID and C_Spell.GetSpellName(spellID)
        local title = L["Config - Menus - Special - Zone"]
        return (name and format("%s: %s", title, name)) or title
    end,

    cooldown = ShownSpellSource,
    state    = ShownSpellSource,

    condition = "zone",
    available = function() return Utils_Spell.GetZoneAbilitySpell() ~= nil end,

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
        scan   = Menu_Kinds.ScanOne(Menu_Kinds.Kind.Zone),
    },
})
