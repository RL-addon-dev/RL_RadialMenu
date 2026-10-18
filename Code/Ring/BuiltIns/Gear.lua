--[[
    Trinkets & On-Use: an equipped-slot action for every gear slot. Each hides while the item in
    that slot has no use effect, so the menu shows what's usable, and picks up on-use gear when you
    equip it.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key      = "gear",
    category = Ring_Data.LibraryCategory.Equipment,
    name     = "Config - Rings - GearRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan     = function() return Ring_Data.MakeSlices(Ring_Kinds.Kind.EquipSlot, Ring_Kinds.GEAR_SLOTS, "slot") end,
})
