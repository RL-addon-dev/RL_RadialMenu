--[[
    Menu data: menus that live elsewhere, meaning other classes' class menus and other characters'
    menus. The settings list them read-only (and can share them), so you can see everything you set
    up without logging in on each character. They're never used in game here.

        Other classes      Their class menus are account-wide (ClassMenus, Store.lua), so they're
                           read as they are.
        Other characters   A character's own menus are saved with it (Local_Persistent), which WoW
                           only loads for that character. So each character keeps a copy of them
                           account-wide, refreshed when it logs in and out, as of its last session.

            RL_RadialMenuDB_Global_Persistent.CharacterMenus["<name>-<realm>"] =
                { name, realm, class, updated (time()), menus = { [id] = menu }, bindings = { [id] = key } }

    Menu ids are unique across scopes and characters (Store.lua's NextMenuId is account-wide), so
    one id names one menu wherever it lives.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")

--- This character's key in the saved copies, "<name>-<realm>".
---@return string
local function CharacterKey()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

--- Every character's saved copy of their menus, by character key.
---@return table
local function GetSnapshots()
    return Private.GetStoredTable(Config.DBGlobalPersistent, "CharacterMenus")
end

-- Copies of this character's menus

--- Copies this character's menus and their keybinds account-wide, or forgets the copy when none
--- are left.
local function SaveSnapshot()
    local menus = Private.GetScopeTable(Menu_Data.Scope.Character)
    local snapshots, key = GetSnapshots(), CharacterKey()
    if not next(menus) then
        snapshots[key] = nil
        return
    end
    snapshots[key] = {
        name = UnitName("player"),
        realm = GetRealmName(),
        class = Private.GetPlayerClass(),
        updated = time(),
        menus = CopyTable(menus),
        bindings = CopyTable(Private.GetBindingTable(Menu_Data.Scope.Character)),
    }
end

CallbackRegistry.Add(env.Event.DataReady, SaveSnapshot)
do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", SaveSnapshot)
end

-- Reading them

--- Calls `callback(class, menus)` for every other class, with that class's saved menus by id.
--- To search, the callback returns what it found. The loop then stops and passes those values on
--- (at most three values, the most any caller needs). To collect, the callback returns nothing,
--- so every class is visited.
---@param callback fun(class: string, menus: table<string, Menu>): any, any, any
---@return any, any, any
local function ForEachOtherClass(callback)
    local current = Private.GetPlayerClass()
    for class, menus in pairs(Private.GetStoredTable(Config.DBGlobalPersistent, "ClassMenus")) do
        if class ~= current and type(menus) == "table" then
            local first, second, third = callback(class, menus)
            if first ~= nil then return first, second, third end
        end
    end
end

--- Calls `callback(snapshot)` for every other character's saved copy that holds menus. It works
--- like ForEachOtherClass. A callback that returns something stops the loop, and its values (at
--- most three) are passed on.
---@param callback fun(snapshot: table): any, any, any
---@return any, any, any
local function ForEachOtherCharacter(callback)
    local current = CharacterKey()
    for characterKey, snapshot in pairs(GetSnapshots()) do
        if characterKey ~= current and type(snapshot) == "table" and type(snapshot.menus) == "table" then
            local first, second, third = callback(snapshot)
            if first ~= nil then return first, second, third end
        end
    end
end

--- Other classes' class menus. They're saved account-wide, so this character can read them. Only
--- a character of that class uses or edits them, and the settings show them read-only.
---@return { menu: Menu, class: string }[] list by class, then name
function Menu_Data.GetOtherClassMenus()
    local list = {}
    ForEachOtherClass(function(class, menus)
        for _, menu in pairs(menus) do
            if type(menu) == "table" and menu.id then list[#list + 1] = { menu = menu, class = class } end
        end
    end)
    table.sort(list, function(a, b)
        if a.class ~= b.class then return a.class < b.class end
        return Private.SortName(a.menu) < Private.SortName(b.menu)
    end)
    return list
end

--- Another class's class menu `id`, read-only (see GetOtherClassMenus).
---@param id string|number?
---@return Menu? menu
---@return string? class its class file name ("WARRIOR")
---@return string? key its keybind on that class
function Menu_Data.GetOtherClassMenu(id)
    if id == nil then return nil end
    id = tostring(id)
    return ForEachOtherClass(function(class, menus)
        if type(menus[id]) ~= "table" then return nil end
        local bindings = Private.GetStoredTable(Config.DBGlobalPersistent, "ClassBindings")[class]
        return menus[id], class, (type(bindings) == "table" and bindings[id]) or nil
    end)
end

--- Other characters' menus (their saved copies), read-only.
---@return { menu: Menu, character: table, key: string? }[] list by character, then name
function Menu_Data.GetOtherCharacterMenus()
    local list = {}
    ForEachOtherCharacter(function(snapshot)
        local bindings = (type(snapshot.bindings) == "table" and snapshot.bindings) or {}
        for id, menu in pairs(snapshot.menus) do
            if type(menu) == "table" then
                list[#list + 1] = { menu = menu, character = snapshot, key = bindings[id] }
            end
        end
    end)
    table.sort(list, function(a, b)
        if a.character.name ~= b.character.name then return (a.character.name or "") < (b.character.name or "") end
        return Private.SortName(a.menu) < Private.SortName(b.menu)
    end)
    return list
end

--- A menu that lives elsewhere, either another class's class menu or another character's menu.
---@param id string|number?
---@return Menu? menu
---@return { class: string, key: string?, character: table? }? owner `character` is the other
---     character's saved copy (name, realm, updated), nil for a class menu
function Menu_Data.GetElsewhereMenu(id)
    if id == nil or Menu_Data.GetMenu(id) then return nil end
    id = tostring(id)
    local menu, class, key = Menu_Data.GetOtherClassMenu(id)
    if menu then return menu, { class = class, key = key } end
    return ForEachOtherCharacter(function(snapshot)
        if type(snapshot.menus[id]) ~= "table" then return nil end
        local bindings = (type(snapshot.bindings) == "table" and snapshot.bindings) or {}
        return snapshot.menus[id], { class = snapshot.class, key = bindings[id], character = snapshot }
    end)
end
