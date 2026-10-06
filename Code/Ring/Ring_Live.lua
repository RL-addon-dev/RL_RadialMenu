--[[
    Menus the way the player sees them. The one place that walks submenus: the in-game menus
    (Ring_Secure), the settings preview, the wheel's badges and the submenu kind's visibility all
    ask here.

    Rules:
        - Actions with nothing to fire are left out (Ring_Actions.IsSliceAvailable).
        - Spread submenus (slice.expand) are replaced by their own actions, at any depth.
        - Scroll submenus (kind "ring", not spread) stay one action: the mouse wheel cycles through
          their scroll list, the submenu's live actions with every submenu inside it spread in
          (whatever its own setting, at any depth). So a menu is at most two levels deep in game:
          the menu you pressed, and a scroll slot's flat list. The wedge shows the current one.
        - A menu never contains itself: loops are refused when editing; walking skips them anyway.

    A live entry: { slice, key, top, ownerId, ownerIndex }
        slice       what fires
        key         its identity (Ring_Data.GetSliceKey), for Last Used
        top         index in the menu being built of the slice it came from
        ownerId / ownerIndex    the menu and index that store it (where a scroll position is kept)
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Live = env.AX_Modules:New("@\\Ring\\Live")

local MAX_DEPTH = 8 -- backstop only; loops are also caught by `visited`

function Ring_Live.IsSubmenu(slice)
    return slice ~= nil and slice.kind == "ring"
end

--- A submenu spread into its parent.
function Ring_Live.IsSpread(slice)
    return Ring_Live.IsSubmenu(slice) and slice.expand == true
end

--- A submenu scrolled with the mouse wheel.
function Ring_Live.IsScroll(slice)
    return Ring_Live.IsSubmenu(slice) and not slice.expand
end

--- @param flatten boolean|nil spread every submenu, scroll ones too (inside a scroll list)
local function AddEntries(entries, slices, ownerId, top, visited, depth, flatten)
    for index, slice in ipairs(slices) do
        if Ring_Actions.IsSliceAvailable(slice) then
            if Ring_Live.IsSpread(slice) or (flatten and Ring_Live.IsSubmenu(slice)) then
                local child = Ring_Data.GetRing(slice.ring)
                if child and not visited[child.id] and depth < MAX_DEPTH then
                    visited[child.id] = true
                    AddEntries(entries, child.slices, child.id, top or index, visited, depth + 1, flatten)
                    visited[child.id] = nil
                end
            else
                entries[#entries + 1] = {
                    slice = slice, key = Ring_Data.GetSliceKey(slice),
                    top = top or index, ownerId = ownerId, ownerIndex = index
                }
            end
        end
    end
end

--- The live entries of `ring` (see the header).
function Ring_Live.GetEntries(ring)
    local entries = {}
    if ring then AddEntries(entries, ring.slices, ring.id, nil, { [ring.id] = true }, 0) end
    return entries
end

--- The ring as the player sees it right now: `entries`, their `slices`, `firstOfTop[i]` (the first
--- live index that came from stored slice i) and the tap-only `quickSlice` while it can fire.
function Ring_Live.Build(ring)
    local entries = Ring_Live.GetEntries(ring)
    local slices, firstOfTop = {}, {}
    for index, entry in ipairs(entries) do
        slices[index] = entry.slice
        firstOfTop[entry.top] = firstOfTop[entry.top] or index
    end
    local quickSlice = ring.quickAction == Ring_Data.QuickAction.Custom and ring.quickSlice
    if quickSlice and not Ring_Actions.IsSliceAvailable(quickSlice) then quickSlice = nil end
    return {
        id = ring.id, name = ring.name, quickAction = ring.quickAction,
        entries = entries, slices = slices, firstOfTop = firstOfTop, quickSlice = quickSlice or nil
    }
end

--- What a scroll submenu slice cycles through: the submenu's actions, with every submenu inside
--- it spread in place (a scroll list is always flat). Empty when it isn't one, or has nothing to
--- show.
function Ring_Live.GetScrollSlices(slice)
    local slices = {}
    local ring = Ring_Live.IsScroll(slice) and Ring_Data.GetRing(slice.ring)
    if not ring then return slices end
    local entries = {}
    AddEntries(entries, ring.slices, ring.id, nil, { [ring.id] = true }, 0, true)
    for index, entry in ipairs(entries) do slices[index] = entry.slice end
    return slices
end

--- Whether submenu `ringId` has submenus of its own (spread into its scroll list when it's one).
function Ring_Live.HasSubmenus(ringId)
    local ring = Ring_Data.GetRing(ringId)
    for _, slice in ipairs(ring and ring.slices or {}) do
        if Ring_Live.IsSubmenu(slice) then return true end
    end
    return false
end

--- The action a wedge shows for `slice`: a scroll submenu shows its current action.
--- @param scrollIndex number|nil position in its scroll list (1 when out of range)
function Ring_Live.GetShownSlice(slice, scrollIndex)
    if not Ring_Live.IsScroll(slice) then return slice end
    local children = Ring_Live.GetScrollSlices(slice)
    return children[scrollIndex or 1] or children[1] or slice
end

--- The action stored slice `index` of `ring` shows, at its remembered scroll position.
function Ring_Live.GetStoredShownSlice(ring, index)
    return Ring_Live.GetShownSlice(ring.slices[index], Ring_Data.GetScrollIndex(ring.id, index))
end

--- How many actions a spread submenu slice adds to its menu right now.
function Ring_Live.CountSpread(slice)
    if not Ring_Live.IsSpread(slice) then return 0 end
    return #Ring_Live.GetEntries(Ring_Data.GetRing(slice.ring))
end

--- Whether menu `ringId` has any action shown right now (a submenu hides while it has none).
function Ring_Live.HasShownSlices(ringId, depth)
    local ring = Ring_Data.GetRing(ringId)
    if not ring or (depth or 0) > MAX_DEPTH then return false end
    for _, slice in ipairs(ring.slices) do
        if Ring_Actions.IsSliceAvailable(slice, (depth or 0) + 1) then return true end
    end
    return false
end
