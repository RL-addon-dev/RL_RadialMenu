--[[
    Ring_Live: menus the way the player sees them. It's the one place that walks submenus, and the
    in-game menus (Ring_Secure), the settings preview, the wheel's badges and the submenu kind's
    visibility all ask here.

    The rules.
        - Actions with nothing to fire are left out (Ring_Actions.IsSliceAvailable).
        - Spread submenus ({ expand = true }) are replaced by their own actions, at any depth.
        - Scroll submenus ({ kind = "ring" }, not spread) stay one action. The mouse wheel cycles
          through their scroll list, which is the submenu's live actions with every submenu inside
          it spread in (whatever its own setting, at any depth). So a menu is at most two levels
          deep in game: the menu you pressed, and a scroll wedge's flat list. The wedge shows the
          current action.
        - A menu never contains itself. Loops are refused when editing, and walking skips them
          anyway.

    A live entry (LiveEntry) is { slice, key, ownerId, ownerIndex }.
        slice       what fires
        key         its identity (Ring_Data.GetSliceKey), for Last Used
        ownerId     the menu that stores it, and its index there (where a scroll position is kept)
        ownerIndex
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Live = env.AX_Modules:New("@\\Ring\\Live")

local MAX_DEPTH = 8 -- only a backstop, since loops are also caught by `visited`

--- Whether `slice` is a submenu, spread or not.
---@param slice Slice?
---@return boolean
function Ring_Live.IsSubmenu(slice)
    return slice ~= nil and slice.kind == Ring_Kinds.Kind.Ring
end

--- Whether `slice` is a submenu spread into its parent.
---@param slice Slice?
---@return boolean
function Ring_Live.IsSpread(slice)
    return Ring_Live.IsSubmenu(slice) and (slice --[[@as Slice]]).expand == true
end

---@param entries LiveEntry[]
---@param slice Slice
---@param ownerId string
---@param index integer
local function AddEntry(entries, slice, ownerId, index)
    entries[#entries + 1] = {
        slice = slice, key = Ring_Data.GetSliceKey(slice),
        ownerId = ownerId, ownerIndex = index
    }
end

--- Whether `slice` is a submenu scrolled with the mouse wheel.
---@param slice Slice?
---@return boolean
function Ring_Live.IsScroll(slice)
    return Ring_Live.IsSubmenu(slice) and not (slice --[[@as Slice]]).expand
end

--- Adds the live entries of `slices` (stored in menu `ownerId`) to `entries`.
---@param entries LiveEntry[]
---@param slices Slice[]
---@param ownerId string
---@param visited table<string, boolean> the menus being walked, to skip loops
---@param depth integer
---@param flatten boolean? spread every submenu, scroll ones too (inside a scroll list)
local function AddEntries(entries, slices, ownerId, visited, depth, flatten)
    for index, slice in ipairs(slices) do
        if Ring_Actions.IsSliceAvailable(slice) then
            if Ring_Live.IsSpread(slice) or (flatten and Ring_Live.IsSubmenu(slice)) then
                local child = Ring_Data.GetRing(slice.ring)
                if child and not visited[child.id] and depth < MAX_DEPTH then
                    visited[child.id] = true
                    AddEntries(entries, child.slices, child.id, visited, depth + 1, flatten)
                    visited[child.id] = nil
                end
            else
                AddEntry(entries, slice, ownerId, index)
            end
        end
    end
end

--- The live entries of `ring` (see the header).
---@param ring Ring?
---@return LiveEntry[]
function Ring_Live.GetEntries(ring)
    local entries = {}
    if ring then AddEntries(entries, ring.slices, ring.id, { [ring.id] = true }, 0) end
    return entries
end

--- The menu as the player sees it right now: `entries`, their `slices`, and the center's
--- `quickSlice` while it can fire.
---@param ring Ring
---@return LiveRing
function Ring_Live.Build(ring)
    local entries = Ring_Live.GetEntries(ring)
    local slices = {}
    for index, entry in ipairs(entries) do slices[index] = entry.slice end
    local quickSlice = Ring_Data.GetQuickActionSlice(ring)
    if quickSlice and not Ring_Actions.IsSliceAvailable(quickSlice) then quickSlice = nil end
    return { id = ring.id, name = ring.name, entries = entries, slices = slices, quickSlice = quickSlice }
end

--- What a scroll submenu cycles through: the submenu's actions, with every submenu inside it
--- spread in place (a scroll list is always flat). It's empty when `slice` isn't one, or has
--- nothing to show.
---@param slice Slice?
---@return Slice[]
function Ring_Live.GetScrollSlices(slice)
    local slices = {}
    local ring = Ring_Live.IsScroll(slice) and Ring_Data.GetRing((slice --[[@as Slice]]).ring)
    if not ring then return slices end
    local entries = {}
    AddEntries(entries, ring.slices, ring.id, { [ring.id] = true }, 0, true)
    for index, entry in ipairs(entries) do slices[index] = entry.slice end
    return slices
end

--- Whether submenu `ringId` has submenus of its own (spread into its scroll list when it's one).
---@param ringId string
---@return boolean
function Ring_Live.HasSubmenus(ringId)
    local ring = Ring_Data.GetRing(ringId)
    for _, slice in ipairs(ring and ring.slices or {}) do
        if Ring_Live.IsSubmenu(slice) then return true end
    end
    return false
end

--- The action a wedge shows for `slice`. A scroll submenu shows its current action.
---@param slice Slice
---@param scrollIndex integer? its position in its scroll list (1 when out of range)
---@return Slice
function Ring_Live.GetShownSlice(slice, scrollIndex)
    if not Ring_Live.IsScroll(slice) then return slice end
    local children = Ring_Live.GetScrollSlices(slice)
    return children[scrollIndex or 1] or children[1] or slice
end

--- The action stored action `index` of `ring` shows, at its remembered scroll position.
---@param ring Ring
---@param index integer
---@return Slice
function Ring_Live.GetStoredShownSlice(ring, index)
    return Ring_Live.GetShownSlice(ring.slices[index], Ring_Data.GetScrollIndex(ring.id, index))
end

--- How many actions a spread submenu adds to its menu right now.
---@param slice Slice?
---@return integer
function Ring_Live.CountSpread(slice)
    if not Ring_Live.IsSpread(slice) then return 0 end
    return #Ring_Live.GetEntries(Ring_Data.GetRing((slice --[[@as Slice]]).ring))
end

--- Whether menu `ringId` has any action shown right now (a submenu hides while it has none).
---@param ringId string
---@param depth integer? how deep in submenus this is asked from, to stop loops
---@return boolean
function Ring_Live.HasShownSlices(ringId, depth)
    local ring = Ring_Data.GetRing(ringId)
    if not ring or (depth or 0) > MAX_DEPTH then return false end
    for _, slice in ipairs(ring.slices) do
        if Ring_Actions.IsSliceAvailable(slice, (depth or 0) + 1) then return true end
    end
    return false
end
