--[[
    Ring data: the store. Menus, their scope, their slices and options.

    Ring_Data is one module spread over Code\Ring\Data\ (see Data.xml):
        Store.lua        this file: storage, ring shape, queries, menu and slice edits
        Keybinds.lua     keybinds (they follow the menu's scope)
        QuickAction.lua  quick action (tap), Last Used
        BuiltIn.lua      built-in menus: automatic contents, remembered order
        Share.lua        sharing menus as text: share string, import plan, import
        Startup.lua      Initialize: saved-data migrations (Migrations\), first-run menus, built-ins
    Helpers they share are in the Private module ("@\\Ring\\Data\\Private"), not public.

    Storage (persistent DBs, so the settings "Reset" doesn't delete rings):
        RL_RadialMenuDB_Global_Persistent.Rings      [id] = ring   account-wide rings
        RL_RadialMenuDB_Global_Persistent.ClassRings [class][id] = ring   class rings (class file name)
        RL_RadialMenuDB_Local_Persistent.Rings       [id] = ring   character rings
        RL_RadialMenuDB_Global_Persistent.Bindings   [id] = key    keybinds of account rings
        RL_RadialMenuDB_Global_Persistent.ClassBindings [class][id] = key   keybinds of class rings
        RL_RadialMenuDB_Local_Persistent.Bindings    [id] = key    keybinds of character rings
        RL_RadialMenuDB_Global_Persistent.NextRingId               id counter (unique across scopes)
        RL_RadialMenuDB_Local_Persistent.LastUsedSlice [id] = key  slice identity (GetSliceKey)
        RL_RadialMenuDB_Local_Persistent.ScrollIndex ["id:N"]      a scroll slice's shown child

    A ring's scope is where it is stored, not a field on the ring: all characters (account), the
    characters of one class (class), or one character.

    Ring:
        id, name
        quickAction:  "none" | "custom" (quickSlice: the action in the center, fired by a tap)
        slices:       array of slices ({ kind = ..., ... }; each kind's fields: Kinds\*.lua)
        builtin:      built-in ring key (Code\Ring\BuiltIns\*.lua); order: its remembered slice
                      order (slice keys)

    Ring behavior shared by all rings (settings in RL_RadialMenuDB_Global, General → Behavior):
        RevealDelay:  seconds before the wheel becomes visible
        Deadzone:     "Distance to Select": px from the key-down spot before a slice is picked
        ProbeSize:    "Distance to Cancel Quick Action": px from the key-down spot (a square twice
                      as wide); leaving it switches the center from quick action to cancel

    Every mutation triggers "Ring.DataChanged".
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:New("@\\Ring\\Data")
local Private = env.AX_Modules:New("@\\Ring\\Data\\Private")
local Ring_Kinds = env.AX_Modules:Await("@\\Ring\\Kinds")
local Ring_Display = env.AX_Modules:Await("@\\Ring\\Display")

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local max = math.max

Ring_Data.Scope = {
    Account   = "account",
    Class     = "class",
    Character = "character"
}
-- Widest to narrowest. Where menus of several scopes use one key, the narrowest one's opens
-- (Ring_Secure binds them in this order).
Ring_Data.ScopeOrder = { Ring_Data.Scope.Account, Ring_Data.Scope.Class, Ring_Data.Scope.Character }

-- quickAction: "none", or "custom": the action in the center (ring.quickSlice), fired by a tap and
-- not on the wheel. Last Used there is a Last Used action (Kinds\LastUsed.lua).
Ring_Data.QuickAction = {
    None   = "none",
    Custom = "custom"
}

-- New menus start without a quick action: releasing in the center then cancels, so an action
-- used last (a Hearthstone, a potion) doesn't fire again by accident.
local RING_DEFAULTS = {
    quickAction = Ring_Data.QuickAction.None,
}

Private.AUTO_ERROR = "this menu fills itself automatically"

-- Fields rings no longer have: per-ring settings that became global ones, and `contents` (how a
-- ring was filled; only built-in rings fill themselves now, by their `builtin` key).
local REMOVED_RING_FIELDS = { "revealDelay", "deadzone", "probeSize", "contents" }

Ring_Data.MIN_PROBE_DISTANCE = 1



-- Ring behavior (global)

function Ring_Data.GetRevealDelay()
    return Config.DBGlobal:GetVariable("RevealDelay")
end

function Ring_Data.GetDeadzone()
    return Config.DBGlobal:GetVariable("Deadzone")
end

--- Side of the square ("Distance to Cancel Quick Action" is its half: the distance you move from
--- the key-down spot). Selecting from the cursor, at most Distance to Select, so its edges never
--- reach past it: once you've been out picking a slice, coming back to the center cancels. With
--- Select From = Menu Center the two are measured from different spots, so there's no cap.
function Ring_Data.GetProbeSize()
    local distance = max(Config.DBGlobal:GetVariable("ProbeSize"), Ring_Data.MIN_PROBE_DISTANCE)
    if not Ring_Display.IsSelectFromMenu() then distance = math.min(distance, Ring_Data.GetDeadzone()) end
    return 2 * distance
end



-- Storage

function Private.GetStoredTable(db, key)
    local stored = _G[db.databaseName]
    if type(stored[key]) ~= "table" then stored[key] = {} end
    return stored[key]
end
local GetStoredTable = Private.GetStoredTable

--- This character's class's table in account-wide `stored[key]` ([class file name] = table).
function Private.GetClassStoredTable(key)
    local byClass = GetStoredTable(Config.DBGlobalPersistent, key)
    local class = select(2, UnitClass("player"))
    if type(byClass[class]) ~= "table" then byClass[class] = {} end
    return byClass[class]
end

function Private.GetScopeTable(scope)
    if scope == Ring_Data.Scope.Character then
        return GetStoredTable(Config.DBLocalPersistent, "Rings")
    elseif scope == Ring_Data.Scope.Class then
        return Private.GetClassStoredTable("ClassRings")
    end
    return GetStoredTable(Config.DBGlobalPersistent, "Rings")
end
local GetScopeTable = Private.GetScopeTable

function Private.Changed()
    CallbackRegistry.Trigger("Ring.DataChanged")
end
local Changed = Private.Changed

--- Fills defaults and drops what a ring may no longer hold. Run after every edit that could
--- leave a ring inconsistent.
function Private.NormalizeRing(ring)
    for key, value in pairs(RING_DEFAULTS) do
        if ring[key] == nil then ring[key] = value end
    end
    for _, key in ipairs(REMOVED_RING_FIELDS) do
        ring[key] = nil
    end
    if type(ring.slices) ~= "table" then ring.slices = {} end
    -- Nested rings used to have an "open" / "scroll" mode; they always scroll now.
    for _, slice in ipairs(ring.slices) do
        if slice.kind == "ring" then slice.nest = nil end
    end
    -- quickSlice only exists while quickAction is Custom. Close in the center is stored as an
    -- empty center: both cancel, and an empty one toggles with Last Used and has no X.
    if ring.quickAction == Ring_Data.QuickAction.Custom
        and (type(ring.quickSlice) ~= "table" or ring.quickSlice.kind == "close") then
        ring.quickAction = Ring_Data.QuickAction.None
    end
    if ring.quickAction ~= Ring_Data.QuickAction.Custom then ring.quickSlice = nil end
end
local NormalizeRing = Private.NormalizeRing

local function NextRingId()
    local stored = _G[Config.DBGlobalPersistent.databaseName]
    local nextId = tonumber(stored.NextRingId) or 1
    while Ring_Data.GetRing(tostring(nextId)) do nextId = nextId + 1 end
    stored.NextRingId = nextId + 1
    return tostring(nextId)
end



-- Queries

--- @return table|nil ring, string|nil scope
function Ring_Data.GetRing(id)
    if id == nil then return nil end
    id = tostring(id)
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        local ring = GetScopeTable(scope)[id]
        if ring then return ring, scope end
    end
end

--- All rings visible to this character, sorted by name then id.
function Ring_Data.GetRings()
    local rings = {}
    for _, scope in pairs(Ring_Data.Scope) do
        for _, ring in pairs(GetScopeTable(scope)) do
            rings[#rings + 1] = ring
        end
    end
    table.sort(rings, function(a, b)
        local nameA, nameB = (a.name or ""):lower(), (b.name or ""):lower()
        if nameA ~= nameB then return nameA < nameB end
        return a.id < b.id
    end)
    return rings
end

--- Scope names for the settings. A class or character menu only exists for its own class or
--- character, so that's always the one playing.
--- The class name in locale string `key` ("%ss" -> "Mages"), in the class color when `colored`.
local function ClassText(key, colored)
    local name, class = UnitClass("player")
    local text = format(env.L[key], name)
    local color = colored and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return color and color.WrapTextInColorCode and color:WrapTextInColorCode(text) or text
end

--- "All Characters", "Mages" or "This Character": the Available On choice.
function Ring_Data.GetScopeName(scope)
    if scope == Ring_Data.Scope.Class then return ClassText("Config - Rings - Scope - Class") end
    return env.L[scope == Ring_Data.Scope.Character and "Config - Rings - Scope - Character" or "Config - Rings - Scope - Account"]
end

--- "your Mages" or "this character": where a class or character menu applies (nil for
--- an account menu: everywhere).
function Ring_Data.GetScopeWhere(scope)
    if scope == Ring_Data.Scope.Class then
        return format(env.L["Config - Rings - Scope - Where - Class"], ClassText("Config - Rings - Scope - Class", true))
    elseif scope == Ring_Data.Scope.Character then
        return env.L["Config - Rings - Scope - Where - Character"]
    end
end

--- "Nevergryn's menu" or "Mage menu" for a character or class menu (its tooltip), nil for an
--- account menu.
function Ring_Data.GetOwnerLabel(id)
    local _, scope = Ring_Data.GetRing(id)
    if scope == Ring_Data.Scope.Character then
        return format(env.L["Config - Rings - CharacterMenu"], UnitName("player"))
    elseif scope == Ring_Data.Scope.Class then
        return format(env.L["Config - Rings - ClassMenu"], (UnitClass("player")))
    end
end

--- Whether `slice` is a submenu this character doesn't have: another class's or another
--- character's menu inside an account menu. It only exists for them, so here it's left out.
function Ring_Data.IsElsewhere(slice)
    return slice.kind == "ring" and Ring_Data.GetRing(slice.ring) == nil
end

--- Whether `slice` can be a quick action: not a submenu or an action bar, which hold several
--- actions (a tap has no single one to fire).
function Ring_Data.CanBeQuickAction(slice)
    if slice.kind == "ring" then return false end
    local definition = Ring_Kinds.Get(slice.kind)
    return not (definition and definition.spread)
end

--- Identity of a slice (the same item / command / slot across refills and moves): Last Used and
--- the built-in menus' remembered order use it.
function Ring_Data.GetSliceKey(slice)
    local value = slice.id or slice.command or slice.slot or slice.guid or slice.ring
        or slice.token or slice.home or slice.name
    -- An action bar ("actionbar:2"), or one of its buttons ("actionslot:2-5").
    if slice.bar then value = slice.button and (slice.bar .. "-" .. slice.button) or slice.bar end
    -- A highest-rank spell isn't the same action as the rank its id names.
    return slice.kind .. ":" .. tostring(value) .. (slice.anyRank and ":any" or "")
end

--- Current child slice of a nested ring slice, remembered per character (1 if never scrolled).
function Ring_Data.GetScrollIndex(ringId, sliceIndex)
    local stored = GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    return stored[tostring(ringId) .. ":" .. sliceIndex] or 1
end

--- Not a ring edit: doesn't fire "Ring.DataChanged".
function Ring_Data.SetScrollIndex(ringId, sliceIndex, childIndex)
    local stored = GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    stored[tostring(ringId) .. ":" .. sliceIndex] = childIndex
end

--- Would making `childId` a nested slice of `parentId` create a loop?
function Ring_Data.WouldCreateCycle(parentId, childId)
    local visited = {}
    local function Reaches(ringId)
        if ringId == parentId then return true end
        if visited[ringId] then return false end
        visited[ringId] = true

        local ring = Ring_Data.GetRing(ringId)
        if not ring then return false end
        for _, slice in ipairs(ring.slices) do
            if slice.kind == "ring" and Reaches(tostring(slice.ring)) then return true end
        end
        return false
    end
    return Reaches(tostring(childId))
end

--- Checks (and normalizes) a slice about to be stored in ring `parentId`, by its kind's `validate`.
--- @return boolean ok, string|nil error
function Ring_Data.ValidateSlice(parentId, slice)
    local definition = type(slice) == "table" and Ring_Kinds.Get(slice.kind)
    if not definition then return false, "unknown action type: " .. tostring(slice and slice.kind) end
    if not definition.validate then return true end

    local ok, err = definition.validate(slice, parentId)
    if not ok then return false, err end
    return true
end



-- Menu edits

--- @param template table|nil fields to start from (copied): slices, quickAction, builtin, ...
--- @return table ring
function Ring_Data.CreateRing(name, scope, template)
    local ring = template and CopyTable(template) or {}
    ring.id = NextRingId()
    ring.name = name or ring.name or ("Ring " .. ring.id)
    ring.binding = nil -- keybinds live in the binding tables (Keybinds.lua)
    NormalizeRing(ring)

    GetScopeTable(scope or Ring_Data.Scope.Account)[ring.id] = ring
    Changed()
    return ring
end

function Ring_Data.DeleteRing(id)
    local ring, scope = Ring_Data.GetRing(id)
    if not ring or Ring_Data.IsBuiltIn(ring) then return false end

    GetScopeTable(scope)[ring.id] = nil
    Private.GetBindingTable(scope)[ring.id] = nil

    -- Remove nested references visible to this character. References from other characters' or
    -- classes' rings stay dangling and are ignored (Ring_Data.IsElsewhere).
    for _, other in ipairs(Ring_Data.GetRings()) do
        for i = #other.slices, 1, -1 do
            local slice = other.slices[i]
            if slice.kind == "ring" and tostring(slice.ring) == ring.id then
                table.remove(other.slices, i)
                Private.RemapSliceIndices(other, function(j)
                    if j == i then return nil end
                    return j > i and j - 1 or j
                end)
            end
        end
        NormalizeRing(other)
    end

    Changed()
    return true
end

function Ring_Data.SetScope(id, scope)
    local ring, currentScope = Ring_Data.GetRing(id)
    if not ring or currentScope == scope or Ring_Data.IsBuiltIn(ring) then return false end

    GetScopeTable(currentScope)[ring.id] = nil
    GetScopeTable(scope)[ring.id] = ring
    Private.MoveBinding(ring.id, currentScope, scope)
    Changed()
    return true
end

function Ring_Data.RenameRing(id, name)
    local ring = Ring_Data.GetRing(id)
    if not ring or Ring_Data.IsBuiltIn(ring) then return false end
    ring.name = name
    Changed()
    return true
end




-- Slice edits

--- After slices move, keep remembered scroll positions (stored by slice index) on the same slice.
--- @param map function(oldIndex) -> newIndex, or nil if that slice is gone
function Private.RemapSliceIndices(ring, map)
    local scroll = GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    local prefix = ring.id .. ":"
    local remembered = {}
    for key, value in pairs(scroll) do
        if key:sub(1, #prefix) == prefix then
            remembered[tonumber(key:sub(#prefix + 1))] = value
            scroll[key] = nil
        end
    end
    for index, value in pairs(remembered) do
        local newIndex = map(index)
        if newIndex then scroll[prefix .. newIndex] = value end
    end
end
local RemapSliceIndices = Private.RemapSliceIndices

--- @param index number|nil position to insert at (default: end)
--- @return boolean ok, string|nil error
function Ring_Data.AddSlice(id, slice, index)
    local ring = Ring_Data.GetRing(id)
    if not ring then return false, "menu not found" end
    if Ring_Data.IsBuiltIn(ring) then return false, Private.AUTO_ERROR end

    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end

    local count = #ring.slices
    index = index and math.min(math.max(index, 1), count + 1) or (count + 1)
    if index <= count then
        RemapSliceIndices(ring, function(i) return i >= index and i + 1 or i end)
    end

    table.insert(ring.slices, index, slice)
    Changed()
    return true
end

--- Moves a slice so it ends up at position `to` (the others shift to make room).
function Ring_Data.MoveSlice(id, from, to)
    local ring = Ring_Data.GetRing(id)
    if not ring or not ring.slices[from] then return false end

    to = math.min(math.max(to, 1), #ring.slices)
    if from == to then return false end

    table.insert(ring.slices, to, table.remove(ring.slices, from))
    RemapSliceIndices(ring, function(i)
        if i == from then return to end
        if from < to and i > from and i <= to then return i - 1 end
        if from > to and i >= to and i < from then return i + 1 end
        return i
    end)
    Private.RememberAutoOrder(ring)

    Changed()
    return true
end

--- Swaps two slices' positions.
function Ring_Data.SwapSlices(id, a, b)
    local ring = Ring_Data.GetRing(id)
    if not ring or a == b or not ring.slices[a] or not ring.slices[b] then return false end

    ring.slices[a], ring.slices[b] = ring.slices[b], ring.slices[a]
    RemapSliceIndices(ring, function(i)
        if i == a then return b end
        if i == b then return a end
        return i
    end)
    Private.RememberAutoOrder(ring)

    Changed()
    return true
end

--- Puts `slice` in place of the slice at `index` (like dropping onto an action bar slot).
--- References to the replaced slice (quick action, last used, scroll position) are dropped.
--- @return boolean ok, string|nil error
function Ring_Data.ReplaceSlice(id, index, slice)
    local ring = Ring_Data.GetRing(id)
    if not ring or not ring.slices[index] then return false, "action not found" end
    if Ring_Data.IsBuiltIn(ring) then return false, Private.AUTO_ERROR end

    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end

    ring.slices[index] = slice
    RemapSliceIndices(ring, function(i) return i ~= index and i or nil end)

    NormalizeRing(ring)
    Changed()
    return true
end

--- Nested ring slices either scroll (default) or expand: their slices are spread into this ring.
function Ring_Data.SetSliceExpand(id, index, expand)
    local ring = Ring_Data.GetRing(id)
    local slice = ring and ring.slices[index]
    if not slice or slice.kind ~= "ring" then return false end
    slice.expand = expand and true or nil
    Changed()
    return true
end

function Ring_Data.RemoveSlice(id, index)
    local ring = Ring_Data.GetRing(id)
    if not ring or not ring.slices[index] then return false end

    if Ring_Data.IsBuiltIn(ring) then
        -- Left out of its refills until restored (BuiltIn.lua).
        Private.RememberRemoved(ring, ring.slices[index])
    end

    table.remove(ring.slices, index)
    RemapSliceIndices(ring, function(i)
        if i == index then return nil end
        return i > index and i - 1 or i
    end)

    NormalizeRing(ring)
    Changed()
    return true
end
