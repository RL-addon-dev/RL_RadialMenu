--[[
    Ring data: menus that live elsewhere: other classes' class menus and other characters' menus.
    The settings list them read-only (and share them), so you can see everything you set up
    without logging in on each character. Never used in game here.

        Other classes      their class menus are account-wide (ClassRings, Store.lua): read as is.
        Other characters   a character's own menus are saved with it (Local_Persistent), which WoW
                           only loads for that character. So each character keeps a copy of them
                           account-wide, refreshed when it logs in and out: as of its last session.

            RL_RadialMenuDB_Global_Persistent.CharacterMenus["<name>-<realm>"] =
                { name, realm, class, updated (time()), rings = { [id] = ring }, bindings = { [id] = key } }

    Menu ids are unique across scopes and characters (Store.lua's NextRingId is account-wide), so
    one id names one menu wherever it lives.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local GetStoredTable = Private.GetStoredTable

local function CharacterKey()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function GetSnapshots()
    return GetStoredTable(Config.DBGlobalPersistent, "CharacterMenus")
end



-- Snapshots of this character's menus

--- Copies this character's menus and their keybinds account-wide (or forgets it: none left).
local function SaveSnapshot()
    local rings = Private.GetScopeTable(Ring_Data.Scope.Character)
    local snapshots, key = GetSnapshots(), CharacterKey()
    if not next(rings) then
        snapshots[key] = nil
        return
    end
    snapshots[key] = {
        name = UnitName("player"),
        realm = GetRealmName(),
        class = select(2, UnitClass("player")),
        updated = time(),
        rings = CopyTable(rings),
        bindings = CopyTable(Private.GetBindingTable(Ring_Data.Scope.Character)),
    }
end

CallbackRegistry.Add("Ring.DataReady", SaveSnapshot)
do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", SaveSnapshot)
end



-- Reading them

--- Other classes' class menus: saved account-wide, so this character can read them (only a
--- character of that class uses or edits them; the settings show them read-only).
--- @return table { { ring = ring, class = "WARRIOR" }, ... } by class, then name
function Ring_Data.GetOtherClassRings()
    local list = {}
    local current = select(2, UnitClass("player"))
    for class, rings in pairs(GetStoredTable(Config.DBGlobalPersistent, "ClassRings")) do
        if class ~= current and type(rings) == "table" then
            for _, ring in pairs(rings) do
                if type(ring) == "table" and ring.id then list[#list + 1] = { ring = ring, class = class } end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.class ~= b.class then return a.class < b.class end
        return (a.ring.name or ""):lower() < (b.ring.name or ""):lower()
    end)
    return list
end

--- Another class's class menu `id` (read-only, see GetOtherClassRings).
--- @return table|nil ring
--- @return string|nil class its class file name ("WARRIOR")
--- @return string|nil key its keybind on that class
function Ring_Data.GetOtherClassRing(id)
    if id == nil then return nil end
    id = tostring(id)
    local current = select(2, UnitClass("player"))
    for class, rings in pairs(GetStoredTable(Config.DBGlobalPersistent, "ClassRings")) do
        if class ~= current and type(rings) == "table" and type(rings[id]) == "table" then
            local bindings = GetStoredTable(Config.DBGlobalPersistent, "ClassBindings")[class]
            return rings[id], class, type(bindings) == "table" and bindings[id] or nil
        end
    end
end

--- Other characters' menus (copies), read-only.
--- @return table { { ring = ring, character = snapshot, key = key|nil }, ... } by character, then name
function Ring_Data.GetOtherCharacterRings()
    local list, current = {}, CharacterKey()
    for characterKey, snapshot in pairs(GetSnapshots()) do
        if characterKey ~= current and type(snapshot) == "table" and type(snapshot.rings) == "table" then
            for id, ring in pairs(snapshot.rings) do
                if type(ring) == "table" then
                    list[#list + 1] = { ring = ring, character = snapshot, key = type(snapshot.bindings) == "table" and snapshot.bindings[id] or nil }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.character.name ~= b.character.name then return (a.character.name or "") < (b.character.name or "") end
        return (a.ring.name or ""):lower() < (b.ring.name or ""):lower()
    end)
    return list
end

--- A menu that lives elsewhere: another class's class menu, or another character's menu.
--- @return table|nil ring
--- @return table|nil owner { class = "WARRIOR", key = keybind there, character = snapshot (another
---     character's: name, realm, updated) }
function Ring_Data.GetElsewhereRing(id)
    if id == nil or Ring_Data.GetRing(id) then return nil end
    id = tostring(id)
    local ring, class, key = Ring_Data.GetOtherClassRing(id)
    if ring then return ring, { class = class, key = key } end
    local current = CharacterKey()
    for characterKey, snapshot in pairs(GetSnapshots()) do
        if characterKey ~= current and type(snapshot) == "table" and type(snapshot.rings) == "table"
            and type(snapshot.rings[id]) == "table" then
            local bindings = type(snapshot.bindings) == "table" and snapshot.bindings or {}
            return snapshot.rings[id], { class = snapshot.class, key = bindings[id], character = snapshot }
        end
    end
end
