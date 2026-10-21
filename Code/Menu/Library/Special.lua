--[[
    Zone and Extra: the Extra Action Button and the zone ability. Both are always in the menu, and
    hide while there's none (their kinds' visibility rules).
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

Menu_Data.RegisterLibraryMenu({
    key      = "special",
    category = Menu_Data.LibraryCategory.Situational,
    name     = "Config - Menus - SpecialMenu - Name",
    versions = { env.GameVersion.Retail },
    scan     = function()
        return { { kind = Menu_Kinds.Kind.Extra }, { kind = Menu_Kinds.Kind.Zone } }
    end,
})
