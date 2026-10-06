--[[
    Talent Loadouts: your current spec's saved loadouts; the active one is hidden (its kind's
    visibility rule). Refills when you switch spec or save, rename or delete a loadout.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

Ring_Data.RegisterBuiltIn({
    key      = "loadouts",
    name     = "Config - Rings - LoadoutRing - Name",
    versions = { env.GameVersion.Retail },
    events   = { "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED" },
    scan     = function()
        local slices = {}
        local _, specID = Ring_Kinds.GetCurrentSpec()
        for _, configID in ipairs(specID and C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
            slices[#slices + 1] = { kind = "loadout", id = configID, spec = specID }
        end
        return slices
    end,
})
