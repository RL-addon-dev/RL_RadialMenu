--[[
    Season Teleports: the Mythic+ dungeon teleports ("Path of ..." spells) you know for the
    current season's dungeons, sorted by dungeon name. A timed +10 earns a dungeon's teleport.

    The season's dungeons are the CURRENT_SEASON list below. Each new season: put its dungeons
    there and comment out the old ones. Below it: earlier seasons (back to Shadowlands, from
    Raider.IO's season data), then every other dungeon with a teleport, by expansion; a spell id
    may appear in more than one section.

    Each entry: { map = challenge map id, spell = teleport spell id (or a list, one per faction),
    name = English name (the client's own name is used when it knows the map) }.
    Map ids: Raider.IO's static data; spell ids as in LibOpenRaid, cross-checked with other addons.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")

-- Midnight Season 2
local CURRENT_SEASON = {
    { map = 588, spell = 1286812, name = "Altar of Fangs" },
    { map = 586, spell = 1286807, name = "Den of Nalorakk" },
    { map = 249, spell = 1286831, name = "Kings' Rest" },
    { map = 587, spell = 1286809, name = "Murder Row" },
    { map = 399, spell = 393256,  name = "Ruby Life Pools" },
    { map = 250, spell = 1286828, name = "Temple of Sethraliss" },
    { map = 584, spell = 1286801, name = "The Blinding Vale" },
    { map = 585, spell = 1286804, name = "Voidscar Arena" },
}

-- Midnight Season 1
-- { map = 402, spell = 393273,  name = "Algeth'ar Academy" },
-- { map = 558, spell = 1254572, name = "Magisters' Terrace" },
-- { map = 560, spell = 1254559, name = "Maisara Caverns" },
-- { map = 559, spell = 1254563, name = "Nexus-Point Xenas" },
-- { map = 556, spell = 1254555, name = "Pit of Saron" },
-- { map = 239, spell = 1254551, name = "Seat of the Triumvirate" },
-- { map = 161, spell = 159898,  name = "Skyreach" },
-- { map = 557, spell = 1254400, name = "Windrunner Spire" },

-- The War Within Season 3
-- { map = 503, spell = 445417, name = "Ara-Kara, City of Echoes" },
-- { map = 542, spell = 1237215, name = "Eco-Dome Al'dani" },
-- { map = 378, spell = 354465, name = "Halls of Atonement" },
-- { map = 525, spell = 1216786, name = "Operation: Floodgate" },
-- { map = 499, spell = 445444, name = "Priory of the Sacred Flame" },
-- { map = 392, spell = 367416, name = "Tazavesh: So'leah's Gambit" },
-- { map = 391, spell = 367416, name = "Tazavesh: Streets of Wonder" },
-- { map = 505, spell = 445414, name = "The Dawnbreaker" },

-- The War Within Season 2
-- { map = 506, spell = 445440, name = "Cinderbrew Meadery" },
-- { map = 504, spell = 445441, name = "Darkflame Cleft" },
-- { map = 525, spell = 1216786, name = "Operation: Floodgate" },
-- { map = 370, spell = 373274, name = "Operation: Mechagon - Workshop" },
-- { map = 499, spell = 445444, name = "Priory of the Sacred Flame" },
-- { map = 247, spell = { 467553, 467555 }, name = "The MOTHERLODE!!" },
-- { map = 500, spell = 445443, name = "The Rookery" },
-- { map = 382, spell = 354467, name = "Theater of Pain" },

-- The War Within Season 1
-- { map = 503, spell = 445417, name = "Ara-Kara, City of Echoes" },
-- { map = 502, spell = 445416, name = "City of Threads" },
-- { map = 507, spell = 445424, name = "Grim Batol" },
-- { map = 375, spell = 354464, name = "Mists of Tirna Scithe" },
-- { map = 353, spell = { 445418, 464256 }, name = "Siege of Boralus" },
-- { map = 505, spell = 445414, name = "The Dawnbreaker" },
-- { map = 376, spell = 354462, name = "The Necrotic Wake" },
-- { map = 501, spell = 445269, name = "The Stonevault" },

-- Dragonflight Season 4
-- { map = 402, spell = 393273, name = "Algeth'ar Academy" },
-- { map = 405, spell = 393267, name = "Brackenhide Hollow" },
-- { map = 406, spell = 393283, name = "Halls of Infusion" },
-- { map = 404, spell = 393276, name = "Neltharus" },
-- { map = 399, spell = 393256, name = "Ruby Life Pools" },
-- { map = 401, spell = 393279, name = "The Azure Vault" },
-- { map = 400, spell = 393262, name = "The Nokhud Offensive" },
-- { map = 403, spell = 393222, name = "Uldaman: Legacy of Tyr" },

-- Dragonflight Season 3
-- { map = 244, spell = 424187, name = "Atal'Dazar" },
-- { map = 199, spell = 424153, name = "Black Rook Hold" },
-- { map = 198, spell = 424163, name = "Darkheart Thicket" },
-- { map = 463, spell = 424197, name = "Dawn of the Infinite: Galakrond's Fall" },
-- { map = 464, spell = 424197, name = "Dawn of the Infinite: Murozond's Rise" },
-- { map = 168, spell = 159901, name = "The Everbloom" },
-- { map = 456, spell = 424142, name = "Throne of the Tides" },
-- { map = 248, spell = 424167, name = "Waycrest Manor" },

-- Dragonflight Season 2
-- { map = 405, spell = 393267, name = "Brackenhide Hollow" },
-- { map = 245, spell = 410071, name = "Freehold" },
-- { map = 406, spell = 393283, name = "Halls of Infusion" },
-- { map = 206, spell = 410078, name = "Neltharion's Lair" },
-- { map = 404, spell = 393276, name = "Neltharus" },
-- { map = 251, spell = 410074, name = "The Underrot" },
-- { map = 438, spell = 410080, name = "The Vortex Pinnacle" },
-- { map = 403, spell = 393222, name = "Uldaman: Legacy of Tyr" },

-- Dragonflight Season 1
-- { map = 402, spell = 393273, name = "Algeth'ar Academy" },
-- { map = 210, spell = 393766, name = "Court of Stars" },
-- { map = 200, spell = 393764, name = "Halls of Valor" },
-- { map = 399, spell = 393256, name = "Ruby Life Pools" },
-- { map = 165, spell = 159899, name = "Shadowmoon Burial Grounds" },
-- { map = 2,   spell = 131204, name = "Temple of the Jade Serpent" },
-- { map = 401, spell = 393279, name = "The Azure Vault" },
-- { map = 400, spell = 393262, name = "The Nokhud Offensive" },

-- Shadowlands Season 4
-- { map = 377, spell = 354468, name = "De Other Side" },
-- { map = 166, spell = 159900, name = "Grimrail Depot" },
-- { map = 378, spell = 354465, name = "Halls of Atonement" },
-- { map = 169, spell = 159896, name = "Iron Docks" },
-- { map = 375, spell = 354464, name = "Mists of Tirna Scithe" },
-- { map = 369, spell = 373274, name = "Operation: Mechagon - Junkyard" },
-- { map = 370, spell = 373274, name = "Operation: Mechagon - Workshop" },
-- { map = 379, spell = 354463, name = "Plaguefall" },
-- { map = 227, spell = 373262, name = "Return to Karazhan: Lower" },
-- { map = 234, spell = 373262, name = "Return to Karazhan: Upper" },
-- { map = 380, spell = 354469, name = "Sanguine Depths" },
-- { map = 381, spell = 354466, name = "Spires of Ascension" },
-- { map = 392, spell = 367416, name = "Tazavesh: So'leah's Gambit" },
-- { map = 391, spell = 367416, name = "Tazavesh: Streets of Wonder" },
-- { map = 376, spell = 354462, name = "The Necrotic Wake" },
-- { map = 382, spell = 354467, name = "Theater of Pain" },

-- Shadowlands Season 3
-- { map = 377, spell = 354468, name = "De Other Side" },
-- { map = 378, spell = 354465, name = "Halls of Atonement" },
-- { map = 375, spell = 354464, name = "Mists of Tirna Scithe" },
-- { map = 379, spell = 354463, name = "Plaguefall" },
-- { map = 380, spell = 354469, name = "Sanguine Depths" },
-- { map = 381, spell = 354466, name = "Spires of Ascension" },
-- { map = 392, spell = 367416, name = "Tazavesh: So'leah's Gambit" },
-- { map = 391, spell = 367416, name = "Tazavesh: Streets of Wonder" },
-- { map = 376, spell = 354462, name = "The Necrotic Wake" },
-- { map = 382, spell = 354467, name = "Theater of Pain" },

-- Shadowlands Season 2
-- { map = 377, spell = 354468, name = "De Other Side" },
-- { map = 378, spell = 354465, name = "Halls of Atonement" },
-- { map = 375, spell = 354464, name = "Mists of Tirna Scithe" },
-- { map = 379, spell = 354463, name = "Plaguefall" },
-- { map = 380, spell = 354469, name = "Sanguine Depths" },
-- { map = 381, spell = 354466, name = "Spires of Ascension" },
-- { map = 376, spell = 354462, name = "The Necrotic Wake" },
-- { map = 382, spell = 354467, name = "Theater of Pain" },

-- Shadowlands Season 1
-- { map = 377, spell = 354468, name = "De Other Side" },
-- { map = 378, spell = 354465, name = "Halls of Atonement" },
-- { map = 375, spell = 354464, name = "Mists of Tirna Scithe" },
-- { map = 379, spell = 354463, name = "Plaguefall" },
-- { map = 380, spell = 354469, name = "Sanguine Depths" },
-- { map = 381, spell = 354466, name = "Spires of Ascension" },
-- { map = 376, spell = 354462, name = "The Necrotic Wake" },
-- { map = 382, spell = 354467, name = "Theater of Pain" },
-- Other dungeons with a teleport, by expansion (a spell list = one per faction)

-- Cataclysm
-- { map = 438, spell = 410080, name = "The Vortex Pinnacle" },
-- { map = 456, spell = 424142, name = "Throne of the Tides" },
-- { map = 507, spell = 445424, name = "Grim Batol" },

-- Mists of Pandaria
-- { map = 2,   spell = 131204, name = "Temple of the Jade Serpent" },
-- { map = 56,  spell = 131205, name = "Stormstout Brewery" },
-- { map = 57,  spell = 131225, name = "Gate of the Setting Sun" },
-- { map = 58,  spell = 131206, name = "Shado-Pan Monastery" },
-- { map = 59,  spell = 131228, name = "Siege of Niuzao Temple" },
-- { map = 60,  spell = 131222, name = "Mogu'shan Palace" },
-- { map = 76,  spell = 131232, name = "Scholomance" },
-- { map = 77,  spell = 131231, name = "Scarlet Halls" },
-- { map = 78,  spell = 131229, name = "Scarlet Monastery" },

-- Warlords of Draenor
-- { map = 161, spell = 159898, name = "Skyreach" },
-- { map = 163, spell = 159895, name = "Bloodmaul Slag Mines" },
-- { map = 164, spell = 159897, name = "Auchindoun" },
-- { map = 165, spell = 159899, name = "Shadowmoon Burial Grounds" },
-- { map = 166, spell = 159900, name = "Grimrail Depot" },
-- { map = 167, spell = 159902, name = "Upper Blackrock Spire" },
-- { map = 168, spell = 159901, name = "The Everbloom" },
-- { map = 169, spell = 159896, name = "Iron Docks" },

-- Legion
-- { map = 198, spell = 424163, name = "Darkheart Thicket" },
-- { map = 199, spell = 424153, name = "Black Rook Hold" },
-- { map = 200, spell = 393764, name = "Halls of Valor" },
-- { map = 206, spell = 410078, name = "Neltharion's Lair" },
-- { map = 210, spell = 393766, name = "Court of Stars" },
-- { map = 227, spell = 373262, name = "Return to Karazhan: Lower" },
-- { map = 234, spell = 373262, name = "Return to Karazhan: Upper" },
-- { map = 239, spell = 1254551, name = "Seat of the Triumvirate" },

-- Battle for Azeroth
-- { map = 244, spell = 424187, name = "Atal'Dazar" },
-- { map = 245, spell = 410071, name = "Freehold" },
-- { map = 247, spell = { 467553, 467555 }, name = "The MOTHERLODE!!" },
-- { map = 248, spell = 424167, name = "Waycrest Manor" },
-- { map = 249, spell = 1286831, name = "Kings' Rest" },
-- { map = 250, spell = 1286828, name = "Temple of Sethraliss" },
-- { map = 251, spell = 410074, name = "The Underrot" },
-- { map = 353, spell = { 445418, 464256 }, name = "Siege of Boralus" },
-- { map = 369, spell = 373274, name = "Operation: Mechagon - Junkyard" },
-- { map = 370, spell = 373274, name = "Operation: Mechagon - Workshop" },

-- Shadowlands
-- { map = 375, spell = 354464, name = "Mists of Tirna Scithe" },
-- { map = 376, spell = 354462, name = "The Necrotic Wake" },
-- { map = 377, spell = 354468, name = "De Other Side" },
-- { map = 378, spell = 354465, name = "Halls of Atonement" },
-- { map = 379, spell = 354463, name = "Plaguefall" },
-- { map = 380, spell = 354469, name = "Sanguine Depths" },
-- { map = 381, spell = 354466, name = "Spires of Ascension" },
-- { map = 382, spell = 354467, name = "Theater of Pain" },
-- { map = 391, spell = 367416, name = "Tazavesh: Streets of Wonder" },
-- { map = 392, spell = 367416, name = "Tazavesh: So'leah's Gambit" },

-- Dragonflight
-- { map = 399, spell = 393256, name = "Ruby Life Pools" },
-- { map = 400, spell = 393262, name = "The Nokhud Offensive" },
-- { map = 401, spell = 393279, name = "The Azure Vault" },
-- { map = 402, spell = 393273, name = "Algeth'ar Academy" },
-- { map = 403, spell = 393222, name = "Uldaman: Legacy of Tyr" },
-- { map = 404, spell = 393276, name = "Neltharus" },
-- { map = 405, spell = 393267, name = "Brackenhide Hollow" },
-- { map = 406, spell = 393283, name = "Halls of Infusion" },
-- { map = 463, spell = 424197, name = "Dawn of the Infinite: Galakrond's Fall" },
-- { map = 464, spell = 424197, name = "Dawn of the Infinite: Murozond's Rise" },

-- The War Within
-- { map = 499, spell = 445444, name = "Priory of the Sacred Flame" },
-- { map = 500, spell = 445443, name = "The Rookery" },
-- { map = 501, spell = 445269, name = "The Stonevault" },
-- { map = 502, spell = 445416, name = "City of Threads" },
-- { map = 503, spell = 445417, name = "Ara-Kara, City of Echoes" },
-- { map = 504, spell = 445441, name = "Darkflame Cleft" },
-- { map = 505, spell = 445414, name = "The Dawnbreaker" },
-- { map = 506, spell = 445440, name = "Cinderbrew Meadery" },
-- { map = 525, spell = 1216786, name = "Operation: Floodgate" },
-- { map = 542, spell = 1237215, name = "Eco-Dome Al'dani" },

local IsKnown = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell

--- The spell (or the one of a faction's spells) you know, or nil.
local function KnownSpell(spell)
    if type(spell) == "table" then
        for _, id in ipairs(spell) do
            if IsKnown(id) then return id end
        end
        return nil
    end
    return spell and IsKnown(spell) and spell or nil
end

--- Teleport spell ids you know for the current season's dungeons, sorted by dungeon name.
local function GetSeasonTeleports()
    local entries, seen = {}, {}
    for _, dungeon in ipairs(CURRENT_SEASON) do
        local spellID = KnownSpell(dungeon.spell)
        if spellID and not seen[spellID] then
            seen[spellID] = true
            local name = C_ChallengeMode.GetMapUIInfo(dungeon.map) or dungeon.name
            entries[#entries + 1] = { spellID = spellID, name = name }
        end
    end
    table.sort(entries, function(a, b) return a.name < b.name end)

    local spellIDs = {}
    for i, entry in ipairs(entries) do spellIDs[i] = entry.spellID end
    return spellIDs
end

Ring_Data.RegisterBuiltIn({
    key    = "season",
    name   = "Config - Rings - SeasonRing - Name",
    versions = { env.GameVersion.Retail },
    events = { "SPELLS_CHANGED" }, -- a teleport learned
    scan   = function()
        local slices = {}
        for i, spellID in ipairs(GetSeasonTeleports()) do slices[i] = { kind = "spell", id = spellID } end
        return slices
    end,
})
