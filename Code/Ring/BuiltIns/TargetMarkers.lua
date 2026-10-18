--[[
    Target Markers: the eight raid target markers (Skull first) for your target, and Clear Target
    Markers, which clears all of them.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key      = "targetmarkers",
    category = Ring_Data.LibraryCategory.Markers,
    name     = "Config - Rings - TargetMarkerRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan     = function() return Ring_Data.MakeSlices(Ring_Kinds.Kind.TargetMarker, Ring_Kinds.TARGET_MARKERS) end,
})
