--[[
    Search for the Menus tab's Add Action panel, and turning what's on the cursor into an action
    (drag and drop). The candidates, id lookups and cursor handlers come from the kind definitions
    (Menu_Kinds, Kinds\*.lua).

    Typing a number also offers what has that id (spell, item, toy or mount), with a note when you
    can't use it right now (a spell you don't know, none in your bags, a mount you haven't
    collected).

    Candidates are cached per kind and rebuilt after the kind's `search.events`, which are listened
    to while the settings are open. All of them are dropped when the settings close.
]]

local env = select(2, ...)
local L = env.L
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Actions = env.AX_Modules:Import("@\\Menu\\Actions")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Utils_Pet = env.AX_Modules:Import("@\\Utils\\Pet")
local Menu_Search = env.AX_Modules:New("@\\Menu\\Search")

local lower, find, sub, format = string.lower, string.find, string.sub, string.format
local tinsert, sort = table.insert, table.sort

local DEFAULT_LIMIT = 40
Menu_Search.ALL = "all" -- the filter entry that searches every kind

-- The filter entries. Menu_Search.ALL comes first, then each kind's `search.filter` in
-- registration order. Several kinds can share one, like "misc" for gear slots and the extra and
-- zone abilities, and their rows still show their own kind.
Menu_Search.Kinds = { Menu_Search.ALL }
do
    local seen = {}
    for _, definition in ipairs(Menu_Kinds.All()) do
        local filter = definition.search and definition.search.filter
        if filter and not seen[filter] then
            seen[filter] = true
            tinsert(Menu_Search.Kinds, filter)
        end
    end
end



-- Candidate lists

--- Adds a candidate for `action` to `list`. The name and icon default to the action's label and
--- icon. The scanner can then set group, order, note, kindLabel and blocked on it.
---@param list SearchCandidate[]
---@param action Action
---@param name string?
---@param icon (number|string)?
---@return SearchCandidate? candidate nil when it has no name
local function AddCandidate(list, action, name, icon)
    name = name or Menu_Actions.GetLabel(action)
    if not name or name == "" then return end
    local definition = Menu_Kinds.Get(action.kind)
    local kind = (definition.search and definition.search.label) or action.kind
    local candidate = { kind = kind, name = name, lname = lower(name), icon = icon or Menu_Actions.GetIcon(action), action = action }
    tinsert(list, candidate)
    return candidate
end

---@param definition KindDefinition
---@param menuId string?
---@return SearchCandidate[]
local function Scan(definition, menuId)
    local list = {}
    definition.search.scan(function(action, name, icon) return AddCandidate(list, action, name, icon) end, menuId)
    return list
end

local cache = {} -- [kind] = SearchCandidate[]

--- A kind's candidates, from the cache unless the kind is `dynamic`.
---@param definition KindDefinition
---@param menuId string?
---@return SearchCandidate[]
local function GetCandidates(definition, menuId)
    if definition.search.dynamic then return Scan(definition, menuId) end
    if not cache[definition.kind] then cache[definition.kind] = Scan(definition) end
    return cache[definition.kind]
end

--- Drops the cached candidates of `kind`, or of every kind when nil.
---@param kind string?
function Menu_Search.Invalidate(kind)
    if kind then cache[kind] = nil else wipe(cache) end
end

-- The lists are only kept, and their sources' events only listened to, while the settings are
-- open. When they close, every list is let go (all your pets, mounts, toys... can be thousands of
-- entries), and the next search builds what it needs again.
do
    local kindsByEvent = {}
    local frame = CreateFrame("Frame")
    for _, definition in ipairs(Menu_Kinds.All()) do
        for _, event in ipairs((definition.search and definition.search.events) or {}) do
            if not kindsByEvent[event] and env.IsEventValid(event) then kindsByEvent[event] = {} end
            if kindsByEvent[event] then tinsert(kindsByEvent[event], definition.kind) end
        end
    end
    frame:SetScript("OnEvent", function(_, event)
        for _, kind in ipairs(kindsByEvent[event]) do Menu_Search.Invalidate(kind) end
        CallbackRegistry.Trigger(env.Event.SearchSourcesChanged)
    end)

    CallbackRegistry.Add(Setting_Enum.Event.HostChanged, function(_, host)
        if host then
            for event in pairs(kindsByEvent) do frame:RegisterEvent(event) end
        else
            frame:UnregisterAllEvents()
            Menu_Search.Invalidate()
        end
    end)
end

--- Offers what `id` is, for every kind that can look one up (and is in `filter`). Anything that
--- exists can be added, and a note says when it can't be used right now.
---@param results SearchCandidate[]
---@param id number
---@param filter string
local function AddIdResults(results, id, filter)
    for _, definition in ipairs(Menu_Kinds.All()) do
        local wanted = filter == Menu_Search.ALL or (definition.search and definition.search.filter == filter)
        if wanted and definition.lookupId then
            local action, note = definition.lookupId(id)
            local candidate = action and AddCandidate(results, action)
            if candidate then candidate.note = note end
        end
    end
end



-- Cursor (drag and drop)

--- The action for what the cursor is holding (a spell, item, toy, macro, mount... being dragged).
---@return Action? action
---@return string? error why it can't be added. Both are nil when the cursor holds nothing.
function Menu_Search.ActionFromCursor()
    local cursorType, info1, info2, info3 = GetCursorInfo()
    if not cursorType then return nil, nil end
    if env.DEBUG_MODE then
        local pickup = cursorType == "petaction" and Utils_Pet.GetLastPetPickup()
        local pickupText = (pickup and format(" (picked up: bar %s, book %s, spell %s)",
            tostring(pickup.barSlot), tostring(pickup.bookSlot), tostring(pickup.spellID))) or ""
        env.Print(format("cursor: %s, %s, %s, %s%s", tostring(cursorType), tostring(info1), tostring(info2), tostring(info3), pickupText))
    end

    for _, definition in ipairs(Menu_Kinds.All()) do
        local handler = definition.cursor and definition.cursor[cursorType]
        local action = handler and handler(info1, info2, info3)
        if action then return action end
    end
    return nil, format(L["Config - Menus - Drop - Unsupported"], cursorType)
end



-- Search

--- How well a candidate matches: 0 for an exact match, 1 when it starts with the query, 2 when it
--- contains it.
---@param candidate SearchCandidate
---@param query string
---@return integer
local function Rank(candidate, query)
    if candidate.lname == query then return 0 end
    if sub(candidate.lname, 1, #query) == query then return 1 end
    return 2
end

--- Searches the actions that can be added to menu `menuId`.
---@param query string
---@param filter string one of Menu_Search.Kinds
---@param menuId string the menu being edited (left out of submenu results, loops refused)
---@param limit integer? DEFAULT_LIMIT when nil
---@return SearchCandidate[] results
---@return boolean truncated whether there were more matches than `limit`
function Menu_Search.Search(query, filter, menuId, limit)
    limit = limit or DEFAULT_LIMIT
    query = lower(strtrim(query or ""))
    local results = {}

    -- A number also offers what has that id.
    local id = tonumber(query)
    if id then AddIdResults(results, id, filter) end

    -- An empty search under All would list everything, so it waits for a query instead.
    if query == "" and filter == Menu_Search.ALL then return results, false end

    -- Each action once. A menu is listed by Menus and by its own filter (Equipment, Misc), and
    -- both are searched under All. The copy with a note wins (an action bar's slots).
    local matches, byKey = {}, {}
    for _, definition in ipairs(Menu_Kinds.All()) do
        local search = definition.search
        if search and search.scan and (filter == Menu_Search.ALL or search.filter == filter) then
            for _, candidate in ipairs(GetCandidates(definition, menuId)) do
                if query == "" or find(candidate.lname, query, 1, true) then
                    local key = Menu_Data.GetActionKey(candidate.action)
                    local seen = byKey[key]
                    if not seen then
                        tinsert(matches, candidate)
                        byKey[key] = #matches
                    elseif candidate.note and not matches[seen].note then
                        matches[seen] = candidate
                    end
                end
            end
        end
    end

    sort(matches, function(a, b)
        local rankA, rankB = Rank(a, query), Rank(b, query)
        if rankA ~= rankB then return rankA < rankB end
        -- Within a match rank, candidates can ask to sort later (like gear slots without a use).
        if (a.group or 0) ~= (b.group or 0) then return (a.group or 0) < (b.group or 0) end
        if a.lname ~= b.lname then return a.lname < b.lname end
        -- The same name keeps the candidate's own order (a spell's ranks, Rank 1 first).
        return (a.order or 0) < (b.order or 0)
    end)

    local room = limit - #results
    for i = 1, math.min(#matches, room) do
        tinsert(results, matches[i])
    end
    return results, #matches > room
end
