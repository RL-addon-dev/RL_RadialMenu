--[[
    Ring data: the store. Queries about menus, and the edits to menus and their actions.

    Ring_Data is one module spread over Code\Ring\Data\ (listed in Data.xml).
        Private.lua      helpers the other files share (the Private module, not public)
        Store.lua        this file, with queries and menu and action edits
        Keybinds.lua     keybinds, which follow the menu's scope
        QuickAction.lua  the quick action (a tap) and Last Used
        BuiltIn.lua      built-in menus, with their automatic contents and remembered order
        Share.lua        sharing menus as text (share string, import plan, import)
        Elsewhere.lua    other classes' and characters' menus, read-only in the settings
        Startup.lua      start-up, with saved-data migrations (Migrations\), first-run menus and
                         built-in menus

    Menus are saved in the persistent databases, so the settings' Reset doesn't delete them.
        RL_RadialMenuDB_Global_Persistent.Rings            [id] = ring          account menus
        RL_RadialMenuDB_Global_Persistent.ClassRings       [class][id] = ring   class menus (class file name)
        RL_RadialMenuDB_Local_Persistent.Rings             [id] = ring          character menus
        RL_RadialMenuDB_Global_Persistent.Bindings         [id] = key           keybinds of account menus
        RL_RadialMenuDB_Global_Persistent.ClassBindings    [class][id] = key    keybinds of class menus
        RL_RadialMenuDB_Local_Persistent.Bindings          [id] = key           keybinds of character menus
        RL_RadialMenuDB_Global_Persistent.NextRingId                            id counter, unique across scopes
        RL_RadialMenuDB_Local_Persistent.LastUsedSlice     [id] = slice key     what each menu fired last
        RL_RadialMenuDB_Local_Persistent.ScrollIndex       ["id:index"] = n     a scroll submenu's shown action

    A menu applies to all characters (account), the characters of one class (class) or one
    character. That scope is where it's stored, not a field on the menu. The fields of menus and
    actions are described in Types.lua (Ring, Slice).

    Every edit fires env.Event.DataChanged.
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Display = env.AX_Modules:Await("@\\Ring\\Display")

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local min, max = math.min, math.max

-- Who a menu applies to (see the header).
Ring_Data.Scope = Utils_Standard.Strict({
    Account   = "account",
    Class     = "class",
    Character = "character"
}, "scope")
-- Widest to narrowest. Where menus of several scopes use one key, the narrowest one's opens
-- (Ring_Secure binds them in this order).
Ring_Data.ScopeOrder = { Ring_Data.Scope.Account, Ring_Data.Scope.Class, Ring_Data.Scope.Character }

-- What a menu's center does on a tap (ring.quickAction). With Custom, it fires ring.quickSlice,
-- which isn't on the wheel. A Last Used center is a Last Used action (Kinds\LastUsed.lua).
Ring_Data.QuickAction = Utils_Standard.Strict({
    None   = "none",
    Custom = "custom"
}, "quick action")

Ring_Data.MIN_PROBE_DISTANCE = 1

-- Settings every menu shares (General tab)

--- Seconds before a held menu's wheel shows.
---@return number
function Ring_Data.GetRevealDelay()
    return Config.Get(Config.Key.RevealDelay)
end

--- Distance to Select, the pixels moved from the key-down spot before an action is picked.
---@return number
function Ring_Data.GetDeadzone()
    return Config.Get(Config.Key.Deadzone)
end

--- The side of the square around the key-down spot. Distance to Cancel Quick Action is half of it,
--- the distance moved before the center switches from the quick action to cancel. When selecting
--- from the cursor, it's at most Distance to Select, so its edges never reach past it. Once you've
--- been out picking an action, coming back to the center cancels. With Select From set to Menu
--- Center, the two are measured from different spots, so there's no cap.
---@return number
function Ring_Data.GetProbeSize()
    local distance = max(Config.Get(Config.Key.ProbeSize), Ring_Data.MIN_PROBE_DISTANCE)
    if not Ring_Display.IsSelectFromMenu() then distance = min(distance, Ring_Data.GetDeadzone()) end
    return 2 * distance
end

--- A new menu id, unique across scopes and characters.
---@return string
local function NextRingId()
    local stored = Config.DBGlobalPersistent:GetData()
    local nextId = tonumber(stored.NextRingId) or 1
    while Ring_Data.GetRing(tostring(nextId)) do nextId = nextId + 1 end
    stored.NextRingId = nextId + 1
    return tostring(nextId)
end

-- Queries

--- This character's menu `id`, and its scope.
---@param id string|number?
---@return Ring? ring
---@return string? scope a Ring_Data.Scope value
function Ring_Data.GetRing(id)
    if id == nil then return nil end
    id = tostring(id)
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        local ring = Private.GetScopeTable(scope)[id]
        if ring then return ring, scope end
    end
end

--- Every menu this character has, sorted by name, then id.
---@return Ring[]
function Ring_Data.GetRings()
    local rings = {}
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        for _, ring in pairs(Private.GetScopeTable(scope)) do
            rings[#rings + 1] = ring
        end
    end
    table.sort(rings, function(a, b)
        local nameA, nameB = Private.SortName(a), Private.SortName(b)
        if nameA ~= nameB then return nameA < nameB end
        return a.id < b.id
    end)
    return rings
end

--- The class name in locale string `key` (which has a %s, like "%ss" for "Mages"), in the class
--- color when `colored`. A class menu only exists for its own class, so that's always the
--- player's.
---@param key string
---@param colored boolean?
---@return string
local function ClassText(key, colored)
    local name, class = UnitClass("player")
    local text = format(L[key], name)
    local color = colored and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return (color and color.WrapTextInColorCode and color:WrapTextInColorCode(text)) or text
end

--- The name of `scope` in the settings' Available On choice, such as "Account", "Mages" or
--- "This Character".
---@param scope string a Ring_Data.Scope value
---@return string
function Ring_Data.GetScopeName(scope)
    if scope == Ring_Data.Scope.Class then return ClassText("Config - Rings - Scope - Class") end
    if scope == Ring_Data.Scope.Character then return L["Config - Rings - Scope - Character"] end
    return L["Config - Rings - Scope - Account"]
end

--- Where a class or character menu applies, such as "your Mages" or "this character". Nil for an
--- account menu, which applies everywhere.
---@param scope string a Ring_Data.Scope value
---@return string?
function Ring_Data.GetScopeWhere(scope)
    if scope == Ring_Data.Scope.Class then
        return format(L["Config - Rings - Scope - Where - Class"], ClassText("Config - Rings - Scope - Class", true))
    elseif scope == Ring_Data.Scope.Character then
        return L["Config - Rings - Scope - Where - Character"]
    end
end

--- Whose menu `id` is, for its tooltip, such as "Nevergryn's menu" or "Mage menu". Works for this
--- character's menus and those of other classes and characters (Elsewhere.lua). Nil for an account
--- menu.
---@param id string|number
---@return string?
function Ring_Data.GetOwnerLabel(id)
    local _, scope = Ring_Data.GetRing(id)
    if scope == Ring_Data.Scope.Character then
        return format(L["Config - Rings - CharacterMenu"], UnitName("player"))
    elseif scope == Ring_Data.Scope.Class then
        return format(L["Config - Rings - ClassMenu"], (UnitClass("player")))
    end
    local _, owner = Ring_Data.GetElsewhereRing(id)
    if owner and owner.character then
        return format(L["Config - Rings - CharacterMenu"], owner.character.name or "?")
    elseif owner then
        local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[owner.class] or owner.class
        return format(L["Config - Rings - ClassMenu"], className)
    end
end

--- Whether `slice` is a submenu this character doesn't have, meaning another class's or another
--- character's menu inside an account menu. It only exists for them, so it's hidden in game and
--- shown as hidden in the settings' preview.
---@param slice Slice
---@return boolean
function Ring_Data.IsElsewhere(slice)
    return slice.kind == Ring_Kinds.Kind.Ring and Ring_Data.GetRing(slice.ring) == nil
end

--- Whether `slice` can be a quick action. Submenus can't, because they hold several actions and a
--- tap has no single one to fire.
---@param slice Slice
---@return boolean
function Ring_Data.CanBeQuickAction(slice)
    return slice.kind ~= Ring_Kinds.Kind.Ring
end

--- The identity of an action, the same across refills and moves, like "item:6948". Last Used and
--- built-in menus' remembered order use it.
---@param slice Slice
---@return string
function Ring_Data.GetSliceKey(slice)
    -- Works for every kind, so it reads whichever kind's identity field the action has.
    local fields = slice --[[@as table]]
    local value = fields.id or fields.command or fields.slot or fields.guid or fields.ring
        or fields.token or fields.home or fields.name
    -- An action bar ("actionbar:2"), or one of its buttons ("actionslot:2-5").
    if fields.bar then value = (fields.button and (fields.bar .. "-" .. fields.button)) or fields.bar end
    -- A highest-rank spell isn't the same action as the rank its id names.
    return fields.kind .. ":" .. tostring(value) .. ((fields.anyRank and ":any") or "")
end

--- Which action a scroll submenu shows, remembered on this character (1 when never scrolled).
---@param ringId string|number the menu holding the submenu
---@param sliceIndex integer the submenu's index in it
---@return integer
function Ring_Data.GetScrollIndex(ringId, sliceIndex)
    local stored = Private.GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    return stored[tostring(ringId) .. ":" .. sliceIndex] or 1
end

--- Remembers which action a scroll submenu shows. This isn't a menu edit, so it doesn't fire
--- env.Event.DataChanged.
---@param ringId string|number
---@param sliceIndex integer
---@param childIndex integer
function Ring_Data.SetScrollIndex(ringId, sliceIndex, childIndex)
    local stored = Private.GetStoredTable(Config.DBLocalPersistent, "ScrollIndex")
    stored[tostring(ringId) .. ":" .. sliceIndex] = childIndex
end

--- Whether adding menu `childId` as a submenu of `parentId` would make them contain each other.
---@param parentId string
---@param childId string|number
---@return boolean
function Ring_Data.WouldCreateCycle(parentId, childId)
    local visited = {}
    local function Reaches(ringId)
        if ringId == parentId then return true end
        if visited[ringId] then return false end
        visited[ringId] = true

        local ring = Ring_Data.GetRing(ringId)
        if not ring then return false end
        for _, slice in ipairs(ring.slices) do
            if slice.kind == Ring_Kinds.Kind.Ring and Reaches(tostring(slice.ring)) then return true end
        end
        return false
    end
    return Reaches(tostring(childId))
end

--- Checks (and normalizes) an action about to be saved in menu `parentId`, with its kind's
--- `validate`.
---@param parentId string? nil when it isn't in a menu yet (imports)
---@param slice Slice
---@return boolean ok
---@return string? error why not, for the chat message
function Ring_Data.ValidateSlice(parentId, slice)
    local definition = type(slice) == "table" and Ring_Kinds.Get(slice.kind)
    if not definition then return false, format(Private.EditError.UnknownKind, tostring(slice and slice.kind)) end
    if not definition.validate then return true end
    return definition.validate(slice, parentId)
end

-- Menu edits

--- Creates a menu in `scope`.
---@param name string?
---@param scope string? a Ring_Data.Scope value (Account by default)
---@param template table? fields to start from, copied (slices, quickAction, builtin, ...)
---@return Ring
function Ring_Data.CreateRing(name, scope, template)
    local ring = (template and CopyTable(template)) or {}
    ring.id = NextRingId()
    ring.name = name or ring.name or L["Config - Rings - NewRing - DefaultName"]
    ring.binding = nil -- keybinds live in the binding tables (Keybinds.lua)
    Private.NormalizeRing(ring)

    Private.GetScopeTable(scope or Ring_Data.Scope.Account)[ring.id] = ring
    Private.Changed()
    return ring
end

--- Deletes menu `id`, and removes it as a submenu from this character's menus. Submenu links in
--- other characters' or classes' menus stay, and are ignored (Ring_Data.IsElsewhere).
---@param id string|number
---@return boolean ok false for a built-in menu, or one that doesn't exist
function Ring_Data.DeleteRing(id)
    local ring, scope = Private.GetEditableRing(id)
    if not ring then return false end

    Private.GetScopeTable(scope)[ring.id] = nil
    Private.GetBindingTable(scope)[ring.id] = nil

    for _, other in ipairs(Ring_Data.GetRings()) do
        for i = #other.slices, 1, -1 do
            local slice = other.slices[i]
            if slice.kind == Ring_Kinds.Kind.Ring and tostring(slice.ring) == ring.id then
                table.remove(other.slices, i)
                Private.ShiftAfterRemove(other, i)
            end
        end
        Private.NormalizeRing(other)
    end

    Private.Changed()
    return true
end

--- Moves menu `id` to another scope. Its keybind moves with it.
---@param id string|number
---@param scope string a Ring_Data.Scope value
---@return boolean ok
function Ring_Data.SetScope(id, scope)
    local ring, currentScope = Private.GetEditableRing(id)
    if not ring or currentScope == scope then return false end

    Private.GetScopeTable(currentScope)[ring.id] = nil
    Private.GetScopeTable(scope)[ring.id] = ring
    Private.MoveBinding(ring.id, currentScope, scope)
    Private.Changed()
    return true
end

---@param id string|number
---@param name string
---@return boolean ok
function Ring_Data.RenameRing(id, name)
    local ring = Private.GetEditableRing(id)
    if not ring then return false end
    ring.name = name
    Private.Changed()
    return true
end

-- Action edits

--- Adds `slice` to menu `id`.
---@param id string|number
---@param slice Slice
---@param index integer? the position it gets (at the end by default)
---@return boolean ok
---@return string? error why not, for the chat message
function Ring_Data.AddSlice(id, slice, index)
    local ring, scopeOrError = Private.GetEditableRing(id)
    if not ring then return false, scopeOrError end

    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end

    local count = #ring.slices
    index = (index and Clamp(index, 1, count + 1)) or (count + 1)
    if index <= count then Private.ShiftAfterInsert(ring, index) end

    table.insert(ring.slices, index, slice)
    Private.Changed()
    return true
end

--- Moves an action so it ends up at position `to`. The others shift to make room.
---@param id string|number
---@param from integer
---@param to integer
---@return boolean ok
function Ring_Data.MoveSlice(id, from, to)
    local ring = Ring_Data.GetRing(id)
    if not ring or not ring.slices[from] then return false end

    to = Clamp(to, 1, #ring.slices)
    if from == to then return false end

    table.insert(ring.slices, to, table.remove(ring.slices, from))
    Private.RemapSliceIndices(ring, function(i)
        if i == from then return to end
        if from < to and i > from and i <= to then return i - 1 end
        if from > to and i >= to and i < from then return i + 1 end
        return i
    end)
    Private.RememberAutoOrder(ring)

    Private.Changed()
    return true
end

--- Swaps two actions' positions.
---@param id string|number
---@param a integer
---@param b integer
---@return boolean ok
function Ring_Data.SwapSlices(id, a, b)
    local ring = Ring_Data.GetRing(id)
    if not ring or a == b or not ring.slices[a] or not ring.slices[b] then return false end

    ring.slices[a], ring.slices[b] = ring.slices[b], ring.slices[a]
    Private.RemapSliceIndices(ring, function(i)
        if i == a then return b end
        if i == b then return a end
        return i
    end)
    Private.RememberAutoOrder(ring)

    Private.Changed()
    return true
end

--- Puts `slice` in place of action `index`, like dropping onto an action bar slot. What referred
--- to the replaced action (the quick action, Last Used, a scroll position) is dropped.
---@param id string|number
---@param index integer
---@param slice Slice
---@return boolean ok
---@return string? error why not, for the chat message
function Ring_Data.ReplaceSlice(id, index, slice)
    local ring, scopeOrError = Private.GetEditableRing(id)
    if not ring then return false, scopeOrError end
    if not ring.slices[index] then return false, Private.EditError.ActionNotFound end

    local ok, err = Ring_Data.ValidateSlice(ring.id, slice)
    if not ok then return false, err end

    ring.slices[index] = slice
    Private.RemapSliceIndices(ring, function(i) return (i ~= index and i) or nil end)

    Private.NormalizeRing(ring)
    Private.Changed()
    return true
end

--- Whether submenu action `index` spreads its actions into the menu (`expand`) or scrolls, which
--- is the default.
---@param id string|number
---@param index integer
---@param expand boolean
---@return boolean ok
function Ring_Data.SetSliceExpand(id, index, expand)
    local ring = Ring_Data.GetRing(id)
    local slice = ring and ring.slices[index]
    if not slice or slice.kind ~= Ring_Kinds.Kind.Ring then return false end
    slice.expand = expand and true or nil
    Private.Changed()
    return true
end

--- Removes action `index`. From a built-in menu, it's also left out of its refills until restored
--- (BuiltIn.lua).
---@param id string|number
---@param index integer
---@return boolean ok
function Ring_Data.RemoveSlice(id, index)
    local ring = Ring_Data.GetRing(id)
    if not ring or not ring.slices[index] then return false end

    if Ring_Data.IsBuiltIn(ring) then Private.RememberRemoved(ring, ring.slices[index]) end

    table.remove(ring.slices, index)
    Private.ShiftAfterRemove(ring, index)

    Private.NormalizeRing(ring)
    Private.Changed()
    return true
end
