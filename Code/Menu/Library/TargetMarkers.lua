--[[
    Target Markers: the eight raid target markers (Skull first) for your target, and Clear Target
    Markers, which clears all of them.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

Menu_Data.RegisterLibraryMenu({
    key      = "targetmarkers",
    category = Menu_Data.LibraryCategory.Markers,
    name     = "Config - Menus - TargetMarkerMenu - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan     = function() return Menu_Data.MakeActions(Menu_Kinds.Kind.TargetMarker, Menu_Kinds.TARGET_MARKERS) end,
})
