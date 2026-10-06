--[[
    Zone and Extra: the Extra Action Button and the zone ability. Both are always in the menu and
    hide while there's none (their kinds' visibility rules).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")

Ring_Data.RegisterBuiltIn({
    key  = "special",
    name = "Config - Rings - SpecialRing - Name",
    versions = { env.GameVersion.Retail },
    scan = function()
        return { { kind = "extra" }, { kind = "zone" } }
    end,
})
