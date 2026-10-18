--[[
    Specializations: every spec of your class; your current one is hidden (its kind's visibility
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
        local slices = {}
        Utils_Spec.ForEachSpec(function(_, specID) slices[#slices + 1] = { kind = Ring_Kinds.Kind.Spec, id = specID } end)
        return slices
    end,
})
