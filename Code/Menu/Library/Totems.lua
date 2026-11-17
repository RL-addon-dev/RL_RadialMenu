--[[
    Totems (WoW Forever): a shaman's totems by element, the ones the totem bar offers for each of
    its slots, and a Totem Utilities menu with the totem bar's summon and Totemic Recall spells
    and Totemic Call, the ones you know. They're cast by id, so each drops that totem straight
    away. The Library only lists the ones this character can use.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

-- The four menus' keys (saved data, never renamed).
local MENU = {
    Earth = "earthtotems",
    Fire  = "firetotems",
    Water = "watertotems",
    Air   = "airtotems",
}
local MENU_ORDER = { MENU.Earth, MENU.Fire, MENU.Water, MENU.Air } -- the totem bar's order
-- The game's totem slot for each (FIRE_TOTEM_SLOT, EARTH_TOTEM_SLOT...).
local SLOT = {
    [MENU.Fire]  = 1,
    [MENU.Earth] = 2,
    [MENU.Water] = 3,
    [MENU.Air]   = 4,
}
local MENU_NAMES = {
    [MENU.Earth] = "Config - Menus - TotemsMenu - Earth",
    [MENU.Fire]  = "Config - Menus - TotemsMenu - Fire",
    [MENU.Water] = "Config - Menus - TotemsMenu - Water",
    [MENU.Air]   = "Config - Menus - TotemsMenu - Air",
}
local VERSIONS = { env.GameVersion.Forever }
-- Utility spells the game's totem bar lists don't have.
local EXTRA_SPELLS = {
    437009, -- Totemic Call
}

---@param key string
---@return boolean
local function HasTotems(key)
    return #Utils_Spell.GetTotemSpells(SLOT[key]) > 0
end

for _, key in ipairs(MENU_ORDER) do
    Menu_Data.RegisterLibraryMenu({
        key      = key,
        category = Menu_Data.LibraryCategory.Character,
        name     = MENU_NAMES[key],
        versions = VERSIONS,
        events   = { "SPELLS_CHANGED" },
        shown    = function() return HasTotems(key) end,
        scan     = function()
            local spellIDs = Utils_Spell.GetTotemSpells(SLOT[key])
            return Menu_Data.MakeActions(Menu_Kinds.Kind.Spell, spellIDs, nil, { byId = true })
        end,
    })
end

--- The totem bar's summon and recall spells, as the game lists them, then EXTRA_SPELLS. Only the
--- ones you know.
---@return number[] spellIDs
local function GetKnownBarSpells()
    local spellIDs = {}
    local lists = {
        _G["TOTEM_MULTI_CAST_SUMMON_SPELLS"], _G["TOTEM_MULTI_CAST_RECALL_SPELLS"], EXTRA_SPELLS,
    }
    for _, list in ipairs(lists) do
        for _, spellID in ipairs(list) do
            if C_SpellBook.IsSpellKnown(spellID) then spellIDs[#spellIDs + 1] = spellID end
        end
    end
    return spellIDs
end

Menu_Data.RegisterLibraryMenu({
    key      = "totemutilities",
    category = Menu_Data.LibraryCategory.Character,
    name     = "Config - Menus - TotemsMenu - Utilities",
    versions = VERSIONS,
    events   = { "SPELLS_CHANGED" },
    shown    = function() return #GetKnownBarSpells() > 0 end,
    scan     = function()
        return Menu_Data.MakeActions(Menu_Kinds.Kind.Spell, GetKnownBarSpells(), nil, { byId = true })
    end,
})
