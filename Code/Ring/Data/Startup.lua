--[[
    Ring data: startup. Runs once the saved variables are ready ("Preload.DatabaseReady"):
    normalizes every ring, runs the migrations that haven't run yet, creates the first-run menus,
    makes sure the built-in menus exist, then fires "Ring.DataReady" (Ring_Secure, Ring_Auto).

    Migrations: one file per change to the saved data, in Migrations\ (listed in order in
    Migrations.xml, which explains the format). Each registers itself here and runs once,
    remembered by its own flag in the saved variables it changes (`db` = "account" or
    "character", so a per character change runs once on every character).
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local MIGRATIONS = {} -- in the order Migrations.xml loads them

--- Registers a saved-data migration (one file in Migrations\). Runs once, at startup.
--- @param migration table { flag = string, db = "account" | "character", run = function(stored) }
function Private.RegisterMigration(migration)
    assert(type(migration.flag) == "string" and type(migration.run) == "function"
        and (migration.db == "account" or migration.db == "character"), "migration needs a flag, a db and run")
    for _, existing in ipairs(MIGRATIONS) do
        assert(existing.flag ~= migration.flag, "migration flag used twice: " .. migration.flag)
    end
    MIGRATIONS[#MIGRATIONS + 1] = migration
end

local function RunMigrations()
    local stores = {
        account   = _G[Config.DBGlobalPersistent.databaseName],
        character = _G[Config.DBLocalPersistent.databaseName],
    }

    for _, migration in ipairs(MIGRATIONS) do
        local stored = stores[migration.db]
        if not stored[migration.flag] then
            stored[migration.flag] = true
            migration.run(stored)
        end
    end
end

-- Menus created on the very first run, as account menus: ring templates ({ name, binding,
-- quickAction, slices }). None for now: new users start with the built-in menus.
local FIRST_RUN_MENUS = {}

local isReady = false

--- Runs once the saved variables are loaded (not tied to combat: only the secure rebuild is).
local function Initialize()
    for _, ring in ipairs(Ring_Data.GetRings()) do
        Private.NormalizeRing(ring)
    end

    RunMigrations()

    local persistent = _G[Config.DBGlobalPersistent.databaseName]
    if not persistent.Seeded then
        persistent.Seeded = true
        if #Ring_Data.GetRings() == 0 then
            for _, template in ipairs(FIRST_RUN_MENUS) do
                local ring = Ring_Data.CreateRing(template.name, Ring_Data.Scope.Account, template)
                if template.binding then Ring_Data.SetBinding(ring.id, template.binding) end
            end
        end
    end

    Private.EnsureBuiltInRings()

    isReady = true
    CallbackRegistry.Trigger("Ring.DataReady")
end

--- Whether the menus are loaded and set up ("Ring.DataReady" has fired).
function Ring_Data.IsReady()
    return isReady
end

CallbackRegistry.Add("Preload.DatabaseReady", Initialize)
