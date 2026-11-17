--[[
    Stances: the spells on your stance bar (warrior stances, druid forms, paladin auras, death
    knight presences, stealth...). The Library only lists it for a character that has a stance bar.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

Menu_Data.RegisterLibraryMenu({
    key      = "stances",
    category = Menu_Data.LibraryCategory.Character,
    name     = "Config - Menus - StancesMenu - Name",
    events   = { "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED" },
    shown    = function() return #Utils_Spell.GetStanceSpells() > 0 end,
    scan     = function()
        return Menu_Data.MakeActions(Menu_Kinds.Kind.Spell, Utils_Spell.GetStanceSpells(), nil, { byId = true })
    end,
})
