--[[
    Talent Loadouts: your current spec's saved loadouts. The active one is hidden (its kind's
    visibility rule). The menu refills when you switch spec, or save, rename or delete a loadout.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spec = env.AX_Modules:Import("@\\Utils\\Spec")

Menu_Data.RegisterLibraryMenu({
    key      = "loadouts",
    category = Menu_Data.LibraryCategory.Character,
    name     = "Config - Menus - LoadoutMenu - Name",
    versions = { env.GameVersion.Retail },
    events   = { "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED" },
    scan     = function()
        local _, specID = Utils_Spec.GetCurrentSpec()
        local configIDs = (specID and C_ClassTalents.GetConfigIDsBySpecID(specID)) or {}
        return Menu_Data.MakeActions(Menu_Kinds.Kind.Loadout, configIDs, nil, { spec = specID })
    end,
})
