--[[
    Specializations: every spec of your class. Your current one is hidden (its kind's visibility
    rule), so the menu offers the specs you can switch to.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Spec = env.AX_Modules:Import("@\\Utils\\Spec")

Ring_Data.RegisterBuiltIn({
    key      = "specs",
    category = Ring_Data.LibraryCategory.Character,
    name     = "Config - Rings - SpecRing - Name",
    versions = { env.GameVersion.Retail },
    events   = { "PLAYER_SPECIALIZATION_CHANGED" },
    scan     = function()
        local specIDs = {}
        Utils_Spec.ForEachSpec(function(_, specID) specIDs[#specIDs + 1] = specID end)
        return Ring_Data.MakeSlices(Ring_Kinds.Kind.Spec, specIDs)
    end,
})
