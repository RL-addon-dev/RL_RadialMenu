--[[
    Menu data: start-up. Runs once the saved variables are ready (env.Event.DatabaseReady), in this
    order.
        1. The migrations that haven't run yet.
        2. Normalizing every menu.
        3. The first-run menus.
        4. Making sure the library menus exist.
        5. Firing env.Event.DataReady (Menu_Secure and Menu_Auto listen).

    Migrations are one file per change to the saved data, in Migrations\ (listed in order in
    Migrations.xml, which explains the format). Each registers itself here and runs once. It's
    remembered by its own flag in the saved variables it changes, so a per character change runs
    once on every character.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")

-- Which saved variables a migration changes (its `db`).
Private.MigrationDB = Utils_Standard.Strict({
    Account   = "account",   -- RL_RadialMenuDB_Global_Persistent, once per account
    Character = "character", -- RL_RadialMenuDB_Local_Persistent, once per character
}, "migration db")

local MIGRATIONS = {} -- in the order Migrations.xml loads them

--- Registers a saved-data migration (one file in Migrations\). It runs once, at start-up.
---@param migration { flag: string, db: string, run: fun(stored: table) } db is a Private.MigrationDB value
function Private.RegisterMigration(migration)
    local db = migration.db
    assert(type(migration.flag) == "string" and type(migration.run) == "function"
        and (db == Private.MigrationDB.Account or db == Private.MigrationDB.Character),
        "migration needs a flag, a db and run")
    for _, existing in ipairs(MIGRATIONS) do
        assert(existing.flag ~= migration.flag, "migration flag used twice: " .. migration.flag)
    end
    MIGRATIONS[#MIGRATIONS + 1] = migration
end

local function RunMigrations()
    local stores = {
        [Private.MigrationDB.Account]   = Config.DBGlobalPersistent:GetData(),
        [Private.MigrationDB.Character] = Config.DBLocalPersistent:GetData(),
    }

    for _, migration in ipairs(MIGRATIONS) do
        local stored = stores[migration.db]
        if not stored[migration.flag] then
            stored[migration.flag] = true
            migration.run(stored)
        end
    end
end

-- Menus created on the very first run, as account menus. Each is a menu template with a name, and
-- optionally a binding, quickAction and actions. There are none for now, so new users start with
-- the library menus.
local FIRST_RUN_MENUS = {}

local isReady = false

--- Runs once the saved variables are loaded. It isn't tied to combat, only the secure rebuild is.
local function Initialize()
    -- Migrations first. They convert old data, which normalizing then checks like any other.
    RunMigrations()
    for _, menu in ipairs(Menu_Data.GetMenus()) do
        Private.NormalizeMenu(menu)
    end

    local persistent = Config.DBGlobalPersistent:GetData()
    if not persistent.Seeded then
        persistent.Seeded = true
        if #Menu_Data.GetMenus() == 0 then
            for _, template in ipairs(FIRST_RUN_MENUS) do
                local menu = Menu_Data.CreateMenu(template.name, Menu_Data.Scope.Account, template)
                if template.binding then Menu_Data.SetBinding(menu.id, template.binding) end
            end
        end
    end

    Private.EnsureLibraryMenus()

    isReady = true
    Private.ForgetOpenableMenus()
    CallbackRegistry.Trigger(env.Event.DataReady)
end

--- Whether the menus are loaded and set up (env.Event.DataReady has fired).
---@return boolean
function Menu_Data.IsReady()
    return isReady
end

CallbackRegistry.Add(env.Event.DatabaseReady, Initialize)
