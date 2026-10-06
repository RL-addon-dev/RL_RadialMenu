--[[
    Trinkets & On-Use: an equipped-slot action for every gear slot. Each hides while the item in
    that slot has no use effect, so the menu shows what's usable and picks up on-use gear when
    you equip it.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key  = "gear",
    name = "Config - Rings - GearRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    scan = function()
        local slices = {}
        for _, slot in ipairs(Ring_Kinds.Get("equipslot").slots) do
            slices[#slices + 1] = { kind = "equipslot", slot = slot }
        end
        return slices
    end,
})
