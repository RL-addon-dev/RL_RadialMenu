--[[
    Trinkets & On-Use: an equipped-slot action for every gear slot. Each hides while the item in
    that slot has no use effect, so the menu shows what's usable, and picks up on-use gear when you
    equip it.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

Menu_Data.RegisterLibraryMenu({
    key      = "gear",
    category = Menu_Data.LibraryCategory.Equipment,
    name     = "Config - Menus - GearMenu - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan     = function() return Menu_Data.MakeActions(Menu_Kinds.Kind.EquipSlot, Menu_Kinds.GEAR_SLOTS, "slot") end,
})
