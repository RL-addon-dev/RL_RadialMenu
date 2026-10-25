--[[
    World Markers: the eight world (ground) markers, placed where the mouse is, and Clear, which
    clears all of them.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

Menu_Data.RegisterLibraryMenu({
    key      = "worldmarkers",
    category = Menu_Data.LibraryCategory.Markers,
    name     = "Config - Menus - WorldMarkerMenu - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan     = function() return Menu_Data.MakeActions(Menu_Kinds.Kind.WorldMarker, Menu_Kinds.WORLD_MARKERS) end,
})
