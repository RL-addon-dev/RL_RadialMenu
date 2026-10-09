--[[
    Ring data: built-in menus. They always exist (created at load), are account-wide, and can't be
    renamed, deleted or added to by hand: Ring_Auto fills their slices. The user can rearrange
    them, and that order is remembered by slice identity (ring.order) across refills.

    The user can remove actions too: they're remembered by identity in ring.removed
    ({ key, label, icon }, name and icon saved for showing them while they aren't around) and
    left out of every refill until restored. New actions still appear.

    Each built-in menu is one file in Code\Ring\BuiltIns\ (listed in BuiltIns.xml):

        Ring_Data.RegisterBuiltIn({
            key    = "quest",                              -- ring.builtin (saved; never rename)
            name   = "Config - Rings - QuestRing - Name",   -- locale key of its (fixed) name
            events = { "QUEST_LOG_UPDATE", ... },          -- refill after these (Ring_Auto)
            scan   = function() return slices end,         -- what it holds right now
            versions = { env.GameVersion.Retail },         -- games it exists in (env.GameVersion,
                                                           -- Preload.lua; leave out for every version)
        })

    Keys are one lowercase word ("targetmarkers"), like action kind names and for the same reason
    (see Ring_Kinds.lua): they're saved data. Renaming one after release needs a migration, or
    the menu is deleted and recreated, losing its keybind and order.

    Its empty text is the locale string "Config - Rings - Auto - Empty - <key>" (optional).
    A built-in menu for other game versions isn't registered (no menu, no events). Its versions
    must be ones where every action kind it uses exists (Ring_Kinds.lua). Built-in rings
    whose key isn't registered (retired, or not for this game) are removed at load; each game
    version keeps its own saved variables.
]]

local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")

local definitions, order = {}, {}

function Ring_Data.RegisterBuiltIn(definition)
    assert(type(definition.key) == "string" and type(definition.scan) == "function", "built-in menu needs a key and a scan")
    if not env.IsForThisGame(definition.versions) then return end
    assert(not definitions[definition.key], "built-in menu registered twice: " .. definition.key)
    definitions[definition.key] = definition
    order[#order + 1] = definition
end

--- Every built-in menu definition, in registration order.
function Ring_Data.GetBuiltInDefinitions()
    return order
end

--- This character's built-in menu with key `key` (ring.builtin), or nil.
function Ring_Data.GetBuiltInRing(key)
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if ring.builtin == key then return ring end
    end
end

--- Built-in menus always exist and fill themselves: they can't be deleted, made per character,
--- renamed, or have slices added / removed by hand.
function Ring_Data.IsBuiltIn(ring)
    return ring ~= nil and ring.builtin ~= nil
end

--- Ring_Auto's refill of a built-in ring. Fires "Ring.DataChanged" with reason "auto", so the
--- secure rebuild it causes (after combat, if needed) doesn't announce itself.
--- Whatever refers to a slice by position (a quick action dragged onto the center) follows that
--- slice to its new position, or is dropped if the slice is gone. A submenu slice keeps its
--- spread / scroll setting (slice.expand), which the user can change on built-in menus too.
function Ring_Data.SetAutoSlices(id, slices)
    local ring = Ring_Data.GetRing(id)
    if not Ring_Data.IsBuiltIn(ring) then return false end

    local newIndex = {}
    for index, slice in ipairs(slices) do
        local key = Ring_Data.GetSliceKey(slice)
        newIndex[key] = newIndex[key] or index
    end
    local oldSlices = ring.slices
    local expandByKey = {}
    for _, slice in ipairs(oldSlices) do
        if slice.expand then expandByKey[Ring_Data.GetSliceKey(slice)] = true end
    end
    for _, slice in ipairs(slices) do
        if expandByKey[Ring_Data.GetSliceKey(slice)] then slice.expand = true end
    end
    Private.RemapSliceIndices(ring, function(index)
        local slice = oldSlices[index]
        return slice and newIndex[Ring_Data.GetSliceKey(slice)]
    end)

    ring.slices = slices
    Private.NormalizeRing(ring)
    CallbackRegistry.Trigger("Ring.DataChanged", "auto")
    return true
end

--- Something the rings show changed outside the ring data (the zone ability): rebuild quietly.
function Ring_Data.NotifyDynamicChange()
    CallbackRegistry.Trigger("Ring.DataChanged", "auto")
end



-- Refilling

local function SameSlices(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if Ring_Data.GetSliceKey(a[i]) ~= Ring_Data.GetSliceKey(b[i]) then return false end
    end
    return true
end

--- Fills built-in `ring` from its definition: what it holds now, minus the actions the user
--- removed, in the order they arranged (new actions at the end). Ring_Auto calls it after the
--- definition's events; restoring an action calls it at once.
function Ring_Data.RefillBuiltIn(ring)
    local definition = ring.builtin and definitions[ring.builtin]
    if not definition then return end
    local removed = {}
    for _, entry in ipairs(ring.removed or {}) do removed[entry.key] = true end
    local slices = {}
    for _, slice in ipairs(definition.scan()) do
        if not removed[Ring_Data.GetSliceKey(slice)] then slices[#slices + 1] = slice end
    end
    slices = Ring_Data.ApplyAutoOrder(ring, slices)
    if not SameSlices(ring.slices, slices) then Ring_Data.SetAutoSlices(ring.id, slices) end
end



-- Removed actions

--- The actions removed from built-in `ring`: { { key, label, icon }, ... }, oldest first.
function Ring_Data.GetRemovedSlices(ring)
    return ring and ring.removed or {}
end

--- Remembers `slice` as removed from built-in `ring` (Ring_Data.RemoveSlice), with its name and
--- icon as they are now.
function Private.RememberRemoved(ring, slice)
    local key = Ring_Data.GetSliceKey(slice)
    ring.removed = ring.removed or {}
    for _, entry in ipairs(ring.removed) do
        if entry.key == key then return end
    end
    ring.removed[#ring.removed + 1] = { key = key, label = Ring_Actions.GetLabel(slice), icon = Ring_Actions.GetIcon(slice) }
end

--- Puts removed action `key` back into built-in menu `id` (every removed action when `key` is
--- nil). It shows again at the next refill, which happens now.
function Ring_Data.RestoreRemoved(id, key)
    local ring = Ring_Data.GetRing(id)
    if not (Ring_Data.IsBuiltIn(ring) and ring.removed) then return false end
    if key then
        for index = #ring.removed, 1, -1 do
            if ring.removed[index].key == key then table.remove(ring.removed, index) end
        end
    else
        wipe(ring.removed)
    end
    if #ring.removed == 0 then ring.removed = nil end
    Ring_Data.RefillBuiltIn(ring)
    Private.Changed() -- the removed list changed, whether or not the menu did
    return true
end



-- Remembered order

--- Built-in rings can be rearranged: remember the order by slice identity so Ring_Auto's refills
--- keep it. Slices not in the ring right now (a quest item you used up) keep their place in the
--- remembered order, after the ones that are.
function Private.RememberAutoOrder(ring)
    if not Ring_Data.IsBuiltIn(ring) then return end
    local keys, seen = {}, {}
    for _, slice in ipairs(ring.slices) do
        local key = Ring_Data.GetSliceKey(slice)
        if not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(ring.order or {}) do
        if not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    ring.order = keys
end

--- Sorts freshly generated slices of a built-in ring into its remembered order; slices it
--- hasn't seen yet go at the end, in the order they were generated.
function Ring_Data.ApplyAutoOrder(ring, slices)
    local rank = {}
    for index, key in ipairs(ring.order or {}) do rank[key] = index end
    local generated = {}
    for index, slice in ipairs(slices) do generated[slice] = index end
    table.sort(slices, function(a, b)
        local ra, rb = rank[Ring_Data.GetSliceKey(a)], rank[Ring_Data.GetSliceKey(b)]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end
        return generated[a] < generated[b]
    end)
    return slices
end



-- Creating them

--- Makes sure every registered built-in ring exists (as an account ring, named in the client's
--- language), and removes built-in rings that aren't registered any more.
function Private.EnsureBuiltInRings()
    local existing = {}
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if ring.builtin and not definitions[ring.builtin] then
            ring.builtin = nil -- DeleteRing refuses built-in rings
            Ring_Data.DeleteRing(ring.id)
        elseif ring.builtin then
            existing[ring.builtin] = ring
        end
    end

    for _, definition in ipairs(order) do
        local name = env.L[definition.name] or definition.key
        local ring = existing[definition.key]
        if ring then
            ring.name = name
        else
            Ring_Data.CreateRing(name, Ring_Data.Scope.Account, { builtin = definition.key, slices = {} })
        end
    end
end
