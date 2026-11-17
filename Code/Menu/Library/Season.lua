--[[
    Season Teleports: the Mythic+ dungeon teleports ("Path of ..." spells) you know for the
    current season's dungeons. A timed +10 earns a dungeon's teleport.

    They come from the game's own flyout for the season, SEASON_FLYOUT below. Each new season,
    put the new "Hero's Path: <season>" flyout's id there. The command above CATEGORIES in
    Flyouts.lua lists every flyout's id and name. Flyouts.lua skips this flyout, so it isn't listed
    twice.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

local SEASON_FLYOUT = 244 -- Hero's Path: Midnight Season 2

Menu_Data.RegisterLibraryMenu({
    key      = "season",
    category = Menu_Data.LibraryCategory.Travel,
    name     = "Config - Menus - SeasonMenu - Name",
    versions = { env.GameVersion.Retail },
    events   = { "SPELLS_CHANGED" }, -- a teleport learned
    scan     = function()
        local spellIDs = Utils_Spell.GetFlyoutSpells(SEASON_FLYOUT)
        return Menu_Data.MakeActions(Menu_Kinds.Kind.Spell, spellIDs)
    end,
})
