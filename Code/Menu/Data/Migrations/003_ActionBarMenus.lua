--[[
    Action bars became library menus (Action Bar 1-8, Library\ActionBars.lua) added as submenus.
    A saved "actionbar" action ({ kind = "actionbar", bar = N }, which spread the bar's buttons
    into its menu) becomes that bar's library menu as a spread submenu, with the same buttons in
    game. Migrations run before start-up creates the library menus, so this makes sure they exist
    first. It runs after 000_SavedNames, so it reads today's names, and the library menus it
    creates go where today's code keeps them.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

-- The retired kind this converts. It's no longer registered, so it isn't in Menu_Kinds.Kind.
local OLD_ACTION_BAR_KIND = "actionbar"

local function ConvertMenus(menus, barMenus)
    if type(menus) ~= "table" then return end
    for _, menu in pairs(menus) do
        for index, action in ipairs(type(menu) == "table" and type(menu.actions) == "table" and menu.actions or {}) do
            local barMenu = type(action) == "table" and action.kind == OLD_ACTION_BAR_KIND and barMenus[action.bar]
            if barMenu then menu.actions[index] = { kind = Menu_Kinds.Kind.Submenu, menu = barMenu.id, spread = true } end
        end
    end
end

local function Run(stored)
    Private.EnsureLibraryMenus()
    local barMenus = {}
    for bar = 1, 8 do barMenus[bar] = Menu_Data.GetActionBarMenu(bar) end

    ConvertMenus(stored.Menus, barMenus)
    -- Class menus are account-wide, so this converts every class's, not only this character's.
    for _, menus in pairs(type(stored.ClassMenus) == "table" and stored.ClassMenus or {}) do
        ConvertMenus(menus, barMenus)
    end
end

Private.RegisterMigration({ flag = "ActionBarMenusAccount", db = Private.MigrationDB.Account, run = Run })
Private.RegisterMigration({ flag = "ActionBarMenusCharacter", db = Private.MigrationDB.Character, run = Run })
