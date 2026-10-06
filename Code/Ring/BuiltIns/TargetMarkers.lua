--[[
    Target Markers: the eight raid target markers (Skull first) for your target, and Clear Target
    Markers (all of them).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key  = "targetmarkers",
    name = "Config - Rings - TargetMarkerRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan = function()
        local slices = {}
        for _, id in ipairs(Ring_Kinds.Get("targetmarker").MARKERS) do slices[#slices + 1] = { kind = "targetmarker", id = id } end
        return slices
    end,
})
