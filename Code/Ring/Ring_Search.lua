--[[
    Search for the Menus tab "Add Action" panel, and drag & drop conversion. The candidates,
    id lookups and cursor handlers come from the kind definitions (Ring_Kinds, Kinds\*.lua).

    Typing a number also offers what has that id (spell / item / toy / mount), with a note when
    you can't use it right now (spell not known, none in your bags, mount not collected).

    Candidates are cached per kind and rebuilt after the kind's `search.events`.
]]

local env = select(2, ...)
local L = env.L
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Search = env.AX_Modules:New("@\\Ring\\Search")

local lower, find, sub, format = string.lower, string.find, string.sub, string.format
local tinsert, sort = table.insert, table.sort

local DEFAULT_LIMIT = 40

-- Filter entries: "all", then each kind's `search.filter` in registration order (several kinds
-- can share one, e.g. "misc" for gear slots and the extra / zone abilities; their rows still
-- show their own kind).
Ring_Search.Kinds = { "all" }
do
    local seen = {}
    for _, definition in ipairs(Ring_Kinds.All()) do
        local filter = definition.search and definition.search.filter
        if filter and not seen[filter] then
            seen[filter] = true
            tinsert(Ring_Search.Kinds, filter)
        end
    end
end



-- Candidate lists

--- Adds a candidate for `slice` to `list`; name / icon default to the slice's label / icon.
--- @return table|nil candidate { kind, name, lname, icon, slice } (plus group / order / note /
--- kindLabel / blocked, set by the scanner)
local function AddCandidate(list, slice, name, icon)
    name = name or Ring_Actions.GetLabel(slice)
    if not name or name == "" then return end
    local definition = Ring_Kinds.Get(slice.kind)
    local kind = definition.search and definition.search.label or slice.kind
    local candidate = { kind = kind, name = name, lname = lower(name), icon = icon or Ring_Actions.GetIcon(slice), slice = slice }
    tinsert(list, candidate)
    return candidate
end

local function Scan(definition, ringId)
    local list = {}
    definition.search.scan(function(slice, name, icon) return AddCandidate(list, slice, name, icon) end, ringId)
    return list
end

local cache = {}

local function GetCandidates(definition, ringId)
    if definition.search.dynamic then return Scan(definition, ringId) end
    if not cache[definition.kind] then cache[definition.kind] = Scan(definition) end
    return cache[definition.kind]
end

--- Drops cached candidates of `kind` (every kind when nil).
function Ring_Search.Invalidate(kind)
    if kind then cache[kind] = nil else wipe(cache) end
end

do
    local kindsByEvent = {}
    local frame = CreateFrame("Frame")
    for _, definition in ipairs(Ring_Kinds.All()) do
        for _, event in ipairs(definition.search and definition.search.events or {}) do
            if not kindsByEvent[event] and env.IsEventValid(event) then
                kindsByEvent[event] = {}
                frame:RegisterEvent(event)
            end
            if kindsByEvent[event] then tinsert(kindsByEvent[event], definition.kind) end
        end
    end
    frame:SetScript("OnEvent", function(_, event)
        for _, kind in ipairs(kindsByEvent[event] or {}) do Ring_Search.Invalidate(kind) end
        CallbackRegistry.Trigger("Ring.SearchSourcesChanged")
    end)
end

--- Offers what `id` is, for every kind that can look one up (and is in the `filter`). Anything
--- that exists can be added; a note says when it can't be used right now.
local function AddIdResults(results, id, filter)
    for _, definition in ipairs(Ring_Kinds.All()) do
        local wanted = filter == "all" or (definition.search and definition.search.filter == filter)
        if wanted and definition.lookupId then
            local slice, note = definition.lookupId(id)
            local candidate = slice and AddCandidate(results, slice)
            if candidate then candidate.note = note end
        end
    end
end



-- Cursor (drag & drop)

--- Slice for what the cursor is holding (a spell, item, toy, macro, mount... being dragged).
--- @return table|nil slice, string|nil error (nil, nil when the cursor holds nothing)
function Ring_Search.SliceFromCursor()
    local cursorType, info1, info2, info3 = GetCursorInfo()
    if not cursorType then return nil, nil end
    if env.DEBUG_MODE then
        local pickup = cursorType == "petaction" and Ring_Kinds.GetLastPetPickup()
        local pickupText = pickup and format(" (picked up: bar %s, book %s, spell %s)",
            tostring(pickup.barSlot), tostring(pickup.bookSlot), tostring(pickup.spellID)) or ""
        env.Print(format("cursor: %s, %s, %s, %s%s", tostring(cursorType), tostring(info1), tostring(info2), tostring(info3), pickupText))
    end

    for _, definition in ipairs(Ring_Kinds.All()) do
        local handler = definition.cursor and definition.cursor[cursorType]
        local slice = handler and handler(info1, info2, info3)
        if slice then return slice end
    end
    return nil, format(L["Config - Rings - Drop - Unsupported"], cursorType)
end



-- Search

--- 0 exact match, 1 starts with the query, 2 contains it.
local function Rank(candidate, query)
    if candidate.lname == query then return 0 end
    if sub(candidate.lname, 1, #query) == query then return 1 end
    return 2
end

--- @param query string
--- @param filter string one of Ring_Search.Kinds
--- @param ringId string the ring being edited (excluded from ring results, loops rejected)
--- @param limit number|nil
--- @return table results each has kind, name, icon, slice
--- @return boolean truncated more matches than `limit`
function Ring_Search.Search(query, filter, ringId, limit)
    limit = limit or DEFAULT_LIMIT
    query = lower(strtrim(query or ""))
    local results = {}

    -- A number: also offer what that id is.
    local id = tonumber(query)
    if id then AddIdResults(results, id, filter) end

    -- An empty "All" search would list everything; wait for a query instead.
    if query == "" and filter == "all" then return results, false end

    local matches = {}
    for _, definition in ipairs(Ring_Kinds.All()) do
        local search = definition.search
        if search and search.scan and (filter == "all" or search.filter == filter) then
            for _, candidate in ipairs(GetCandidates(definition, ringId)) do
                if query == "" or find(candidate.lname, query, 1, true) then
                    tinsert(matches, candidate)
                end
            end
        end
    end

    sort(matches, function(a, b)
        local ra, rb = Rank(a, query), Rank(b, query)
        if ra ~= rb then return ra < rb end
        -- Within a match rank, candidates can ask to sort later (e.g. gear slots without a use).
        if (a.group or 0) ~= (b.group or 0) then return (a.group or 0) < (b.group or 0) end
        if a.lname ~= b.lname then return a.lname < b.lname end
        -- The same name: in the candidate's own order (a spell's ranks, Rank 1 first).
        return (a.order or 0) < (b.order or 0)
    end)

    local room = limit - #results
    for i = 1, math.min(#matches, room) do
        tinsert(results, matches[i])
    end
    return results, #matches > room
end
