--[[
    World Markers: the eight world (ground) markers, placed where the mouse is, and Clear all.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key  = "worldmarkers",
    name = "Config - Rings - WorldMarkerRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan = function()
        local slices = {}
        for _, id in ipairs(Ring_Kinds.Get("worldmarker").MARKERS) do slices[#slices + 1] = { kind = "worldmarker", id = id } end
        return slices
    end,
})
