--[[
    Zone and Extra: the Extra Action Button and the zone ability. Both are always in the menu, and
    hide while there's none (their kinds' visibility rules).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key      = "special",
    category = Ring_Data.LibraryCategory.Situational,
    name     = "Config - Rings - SpecialRing - Name",
    versions = { env.GameVersion.Retail },
    scan     = function()
        return { { kind = Ring_Kinds.Kind.Extra }, { kind = Ring_Kinds.Kind.Zone } }
    end,
})
