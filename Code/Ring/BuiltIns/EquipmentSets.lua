--[[
    Equipment Sets: your Equipment Manager sets. The one you're wearing is hidden (its kind's
    visibility rule), so the menu offers the sets you can switch to.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Ring_Data.RegisterBuiltIn({
    key      = "equipsets",
    category = Ring_Data.LibraryCategory.Equipment,
    name     = "Config - Rings - EquipSetRing - Name",
    events   = { "EQUIPMENT_SETS_CHANGED" },
    scan     = function()
        local names = {}
        Utils_Item.ForEachEquipmentSet(function(name) names[#names + 1] = name end)
        return Ring_Data.MakeSlices(Ring_Kinds.Kind.EquipSet, names, "name")
    end,
})
