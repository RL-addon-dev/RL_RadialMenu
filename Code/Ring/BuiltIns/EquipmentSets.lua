--[[
    Equipment Sets: your Equipment Manager sets; the one you're wearing is hidden (its kind's
    visibility rule), so the menu offers the sets you can switch to.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key    = "equipsets",
    name   = "Config - Rings - EquipSetRing - Name",
    events = { "EQUIPMENT_SETS_CHANGED" },
    scan   = function()
        local slices = {}
        Ring_Kinds.ForEachEquipmentSet(function(name) slices[#slices + 1] = { kind = "equipset", name = name } end)
        return slices
    end,
})
