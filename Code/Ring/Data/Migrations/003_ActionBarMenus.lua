--[[
    Action bars became built-in menus (Action Bar 1-8, BuiltIns\ActionBars.lua) added as submenus.
    A saved "actionbar" action ({ kind = "actionbar", bar = N }, which spread the bar's buttons
    into its menu) becomes that bar's built-in menu as a spread submenu, with the same buttons in
    game. Migrations run before start-up creates the built-in menus, so this makes sure they exist
    first.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

-- The retired kind this converts. It's no longer registered, so it isn't in Ring_Kinds.Kind.
local OLD_ACTION_BAR_KIND = "actionbar"

local function ConvertRings(rings, barMenus)
    if type(rings) ~= "table" then return end
    for _, ring in pairs(rings) do
        for index, slice in ipairs(type(ring) == "table" and type(ring.slices) == "table" and ring.slices or {}) do
            local menu = type(slice) == "table" and slice.kind == OLD_ACTION_BAR_KIND and barMenus[slice.bar]
            if menu then ring.slices[index] = { kind = Ring_Kinds.Kind.Ring, ring = menu.id, expand = true } end
        end
    end
end

local function Run(stored)
    Private.EnsureBuiltInRings()
    local barMenus = {}
    for bar = 1, 8 do barMenus[bar] = Ring_Data.GetActionBarRing(bar) end

    ConvertRings(stored.Rings, barMenus)
    -- Class menus are account-wide, so this converts every class's, not only this character's.
    for _, rings in pairs(type(stored.ClassRings) == "table" and stored.ClassRings or {}) do
        ConvertRings(rings, barMenus)
    end
end

Private.RegisterMigration({ flag = "ActionBarMenusAccount", db = Private.MigrationDB.Account, run = Run })
Private.RegisterMigration({ flag = "ActionBarMenusCharacter", db = Private.MigrationDB.Character, run = Run })
