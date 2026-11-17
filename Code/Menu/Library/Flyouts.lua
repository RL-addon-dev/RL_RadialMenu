--[[
    Flyouts: one library menu per flyout the game has (Portal, Teleport, Summon Demon, Call Pet...),
    holding its spells you know, cast by name like the Spellbook menu, so a spell that's replaced
    (Switch Flight Style) casts what it is now. Every class's flyouts are registered on every
    character, so the menus keep their keybinds and order across characters. The Library only
    lists the ones this character knows.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

-- Flyouts with no menu of their own, because another flyout already has their spells.
local SKIPPED_FLYOUTS = {
    [243] = true, -- Switch Flight Style (in Skyriding)
    [244] = true, -- Hero's Path: Midnight Season 2 (Season Teleports, Season.lua)
}

local Category = Menu_Data.LibraryCategory
-- Each flyout's Library group. The ones not listed go in Flyouts. The ids and names come from
-- this command in game (Retail), which lists every flyout:
-- /run for i=1,GetNumFlyouts() do local f=GetFlyoutID(i) print(f,(GetFlyoutInfo(f))) end
local CATEGORIES = {
    -- Travel
    [1]   = Category.Travel, -- Teleport
    [8]   = Category.Travel, -- Teleport
    [11]  = Category.Travel, -- Portal
    [12]  = Category.Travel, -- Portal
    [84]  = Category.Travel, -- Hero's Path: Mists of Pandaria
    [96]  = Category.Travel, -- Hero's Path: Warlords of Draenor
    [220] = Category.Travel, -- Hero's Path: Shadowlands
    [222] = Category.Travel, -- Hero's Path: Shadowlands Raids
    [223] = Category.Travel, -- Hero's Path: Battle for Azeroth
    [224] = Category.Travel, -- Hero's Path: Legion
    [227] = Category.Travel, -- Hero's Path: Dragonflight
    [229] = Category.Travel, -- Skyriding
    [230] = Category.Travel, -- Hero's Path: Cataclysm
    [231] = Category.Travel, -- Hero's Path: Dragonflight Raids
    [232] = Category.Travel, -- Hero's Path: The War Within
    [242] = Category.Travel, -- Hero's Path: War Within Raids
    [246] = Category.Travel, -- Hero's Path: Midnight
    [274] = Category.Travel, -- Hero's Path: Wrath of the Lich King
    -- Character (class and profession flyouts)
    [9]   = Category.Character, -- Call Pet
    [10]  = Category.Character, -- Summon Demon
    [66]  = Category.Character, -- Poisons
    [67]  = Category.Character, -- Grimoire of Service
    [92]  = Category.Character, -- Polymorph Variants
    [93]  = Category.Character, -- Exotic Munitions
    [103] = Category.Character, -- Pet Utility
    [106] = Category.Character, -- Hex Variants
    [219] = Category.Character, -- Adaptation
    [225] = Category.Character, -- Hunter Tracking
    [226] = Category.Character, -- Track Gathering Profession Reagents
    [236] = Category.Character, -- Number Sequences
    [238] = Category.Character, -- Sharpen Your Knife
    [239] = Category.Character, -- Overload Herbs
    [240] = Category.Character, -- Overload Ore
    [241] = Category.Character, -- Green Thumb
    [245] = Category.Character, -- Carve Meat
    [247] = Category.Character, -- Traps
    -- Situational
    [217] = Category.Situational, -- Kyrian Instruments
    [235] = Category.Situational, -- Warbands
    [237] = Category.Situational, -- Perennius's Sky Arsenal
}

for _, flyoutID in ipairs(Utils_Spell.GetFlyoutIDs()) do
    if not SKIPPED_FLYOUTS[flyoutID] then
        Menu_Data.RegisterLibraryMenu({
            key      = "flyout" .. flyoutID, -- saved data, so never changed
            category = CATEGORIES[flyoutID] or Category.Flyouts,
            label    = Utils_Spell.GetFlyoutName(flyoutID),
            events   = { "SPELLS_CHANGED" },
            shown    = function() return Utils_Spell.IsFlyoutKnown(flyoutID) end,
            scan     = function()
                local spellIDs = Utils_Spell.GetFlyoutSpells(flyoutID)
                return Menu_Data.MakeActions(Menu_Kinds.Kind.Spell, spellIDs)
            end,
        })
    end
end
