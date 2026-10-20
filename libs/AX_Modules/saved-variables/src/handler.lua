local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local SavedVariables_Enum = env.AX_Modules:Import("ax_modules\\saved-variables\\enum")
local SavedVariables_Handler = env.AX_Modules:New("ax_modules\\saved-variables\\handler")

local type = type
local pairs = pairs

local registeredDatabases = {}

--- A saved variables table with defaults (SavedVariables.RegisterDatabase). Calls take the
--- database: db:GetVariable(key).
---@class SavedVariablesDatabase
---@field SetVariable fun(self: SavedVariablesDatabase, key: string, value: any) saves it, firing OnChange when it changed
---@field GetVariable fun(self: SavedVariablesDatabase, key: string): any its value, or its default
---@field ResetVariable fun(self: SavedVariablesDatabase, key: string) back to its default, firing OnChange
---@field Wipe fun(self: SavedVariablesDatabase) empties it (no OnChange)
---@field GetData fun(self: SavedVariablesDatabase): table the saved table itself
---@field defaults fun(defaults: table): SavedVariablesDatabase sets the defaults, as db.defaults(table)
---@field migrationPlan fun(schema: table[]): SavedVariablesDatabase moves old keys, as db.migrationPlan(schema)

--- The database's saved table itself (created if the game hasn't made it yet). Use it for data
--- that isn't a variable with a default, like lists the addon manages on its own.
---@return table
local function GetStoredData(self)
    local storedData = _G[self.databaseName]
    if storedData == nil then
        storedData = {}
        _G[self.databaseName] = storedData
    end
    return storedData
end

local function ResolveNestedPath(rootTable, pathKeys)
    local current = rootTable
    for i = 1, #pathKeys do
        if current == nil then return nil end
        current = current[pathKeys[i]]
    end
    return current
end

local function SetVariable(self, key, value)
    local storedData = GetStoredData(self)
    local previousValue = storedData[key]

    if previousValue == value then return end
    if type(value) == "table" and previousValue == value then return end

    storedData[key] = value
    CallbackRegistry.Trigger(self.callbackPrefix .. key, value)
end

local function GetVariable(self, key)
    local storedValue = GetStoredData(self)[key]
    if storedValue ~= nil then return storedValue end
    return self.defaultValues[key]
end

local function ResetVariable(self, key)
    local defaultValue = self.defaultValues[key]
    local storedData = GetStoredData(self)

    if storedData[key] ~= defaultValue then
        storedData[key] = defaultValue
        CallbackRegistry.Trigger(self.callbackPrefix .. key, defaultValue)
    end
end

local function WipeDatabase(self)
    _G[self.databaseName] = {}
end

local function SetDefaults(self, defaultsTable)
    self.defaultValues = defaultsTable
    return self
end

local function Migrate(self, migrationSchema)
    local storedData = GetStoredData(self)
    if not storedData or type(migrationSchema) ~= "table" then return self end

    for i = 1, #migrationSchema do
        local migration = migrationSchema[i]
        local migrationType = migration.migrationType

        local sourceIsPath = type(migration.from) == "table"
        local destinationIsPath = type(migration.to) == "table"

        local sourceValue = sourceIsPath and ResolveNestedPath(storedData, migration.from) or storedData[migration.from]
        local destinationKey = destinationIsPath and ResolveNestedPath(storedData, migration.to) or migration.to

        if migrationType == "group" and sourceValue and destinationKey then
            local targetTable = destinationIsPath and destinationKey
                or (migration.to == SavedVariables_Enum.Root and storedData)
                or storedData[migration.to]

            if targetTable then
                for sourceKey, sourceVal in pairs(sourceValue) do
                    if targetTable[sourceKey] == nil then
                        targetTable[sourceKey] = sourceVal
                        sourceValue[sourceKey] = nil
                    end
                end
            end
        elseif migrationType == "variable" and sourceValue and destinationKey and storedData[destinationKey] == nil then
            storedData[destinationKey] = sourceValue
            storedData[migration.from] = nil
        elseif migrationType == "delete" and destinationKey then
            storedData[destinationKey] = nil
        end
    end
    return self
end

local databaseMetatable = {
    __index = function(self, key)
        if key == "defaults" then
            return function(defaultsTable)
                return SetDefaults(self, defaultsTable)
            end
        elseif key == "migrationPlan" then
            return function(migrationSchema)
                return Migrate(self, migrationSchema)
            end
        end
    end
}

--- The database for saved variable `databaseName` (the .toc's SavedVariables name), registered.
---@param databaseName string
---@return SavedVariablesDatabase
function SavedVariables_Handler.RegisterDatabase(databaseName)
    if not _G[databaseName] then _G[databaseName] = {} end

    local callbackPrefix = "SavedVariables." .. databaseName .. "."
    local databaseEntry = {
        SetVariable    = SetVariable,
        GetVariable    = GetVariable,
        ResetVariable  = ResetVariable,
        Wipe           = WipeDatabase,
        GetData        = GetStoredData,
        databaseName   = databaseName,
        defaultValues  = {},
        callbackPrefix = callbackPrefix
    }
    setmetatable(databaseEntry, databaseMetatable)

    registeredDatabases[databaseName] = databaseEntry
    return databaseEntry
end

--- Forgets database `databaseName` (its saved table stays).
---@param databaseName string
function SavedVariables_Handler.RemoveDatabase(databaseName)
    registeredDatabases[databaseName] = nil
end

--- Database `databaseName`, or nil when it isn't registered.
---@param databaseName string
---@return SavedVariablesDatabase?
function SavedVariables_Handler.GetDatabase(databaseName)
    return registeredDatabases[databaseName]
end

--- Calls `callbackFunc(id, value)` when `variableName` is changed by SetVariable or ResetVariable.
---@param databaseName string
---@param variableName string
---@param callbackFunc fun(id: string, value: any)
function SavedVariables_Handler.OnChange(databaseName, variableName, callbackFunc)
    CallbackRegistry.Add("SavedVariables." .. databaseName .. "." .. variableName, callbackFunc)
end
