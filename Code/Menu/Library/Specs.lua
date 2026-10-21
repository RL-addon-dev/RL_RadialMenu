--[[
    Specializations: every spec of your class. Your current one is hidden (its kind's visibility
    rule), so the menu offers the specs you can switch to.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spec = env.AX_Modules:Import("@\\Utils\\Spec")

Menu_Data.RegisterLibraryMenu({
    key      = "specs",
    category = Menu_Data.LibraryCategory.Character,
    name     = "Config - Menus - SpecMenu - Name",
    versions = { env.GameVersion.Retail },
    events   = { "PLAYER_SPECIALIZATION_CHANGED" },
    scan     = function()
        local specIDs = {}
        Utils_Spec.ForEachSpec(function(_, specID) specIDs[#specIDs + 1] = specID end)
        return Menu_Data.MakeActions(Menu_Kinds.Kind.Spec, specIDs)
    end,
})
