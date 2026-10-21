--[[
    Equipment Sets: your Equipment Manager sets. The one you're wearing is hidden (its kind's
    visibility rule), so the menu offers the sets you can switch to.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

Menu_Data.RegisterLibraryMenu({
    key      = "equipsets",
    category = Menu_Data.LibraryCategory.Equipment,
    name     = "Config - Menus - EquipSetMenu - Name",
    events   = { "EQUIPMENT_SETS_CHANGED" },
    scan     = function()
        local names = {}
        Utils_Item.ForEachEquipmentSet(function(name) names[#names + 1] = name end)
        return Menu_Data.MakeActions(Menu_Kinds.Kind.EquipSet, names, "name")
    end,
})
