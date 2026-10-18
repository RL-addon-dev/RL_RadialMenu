--[[
    World Markers: the eight world (ground) markers, placed where the mouse is, and Clear, which
    clears all of them.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key      = "worldmarkers",
    category = Ring_Data.LibraryCategory.Markers,
    name     = "Config - Rings - WorldMarkerRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan     = function() return Ring_Data.MakeSlices(Ring_Kinds.Kind.WorldMarker, Ring_Kinds.WORLD_MARKERS) end,
})
