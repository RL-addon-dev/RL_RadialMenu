--[[
    What an action does and shows: its secure action button attributes, icon, label, cooldown
    source and visibility. The per-kind logic lives in the kind definitions (Ring_Kinds,
    Kinds\*.lua), and this is the interface the rest of the addon uses.

    Any action can override how it's shown.
        icon    an icon (number or path) instead of its kind's
        label   a name instead of its kind's
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Actions = env.AX_Modules:New("@\\Ring\\Actions")

-- Every secure attribute a kind may set. They're cleared before applying an action, so nothing is
-- left over from what this suffix held before a rebuild (another action, or another mode of the
-- same one).
local SLICE_ATTRIBUTES = { "type", "spell", "item", "toy", "macro", "macrotext", "action", "marker", "unit", "clickbutton",
    "pagedbutton", -- Action Bar 1 buttons follow the bar's page (Kinds\ActionBar.lua)
    "close",       -- a Close action, where picking it is a cancel (Kinds\Close.lua)
    "lastused",    -- a Last Used action, which fires the menu's last used action (Kinds\LastUsed.lua)
    "first" }      -- a First Action, which fires the menu's first wedge (Kinds\First.lua)

--- Sets the attributes for `slice` under button suffix `suffix` ("*type-<suffix>", ...). Call it
--- out of combat.
---@param button Button
---@param suffix string
---@param slice Slice
function Ring_Actions.ApplySliceSuffix(button, suffix, slice)
    for _, name in ipairs(SLICE_ATTRIBUTES) do
        Ring_Kinds.SetAttribute(button, name, suffix, nil)
    end
    local definition = Ring_Kinds.Get(slice.kind)
    if definition and definition.apply then
        definition.apply(button, suffix, slice)
    else
        Ring_Kinds.ClearAction(button, suffix)
    end
end

--- Sets the attributes for `slice` as the menu button's action `index`. Call it out of combat.
---@param button Button
---@param index integer
---@param slice Slice
function Ring_Actions.ApplySlice(button, index, slice)
    Ring_Actions.ApplySliceSuffix(button, "s" .. index, slice)
end

--- The icon `slice` shows, or the question mark when its kind has none right now.
---@param slice Slice
---@param depth integer? how deep in submenus it's asked from (submenus show a child's icon)
---@return number|string
function Ring_Actions.GetIcon(slice, depth)
    if slice.icon then return slice.icon end
    local definition = Ring_Kinds.Get(slice.kind)
    return (definition and definition.icon and definition.icon(slice, depth or 0)) or Ring_Kinds.QUESTION_MARK_ICON
end

--- Whether `slice`'s icon is shown without the action button border (its kind's noIconBorder).
---@param slice Slice
---@return boolean
function Ring_Actions.HasNoIconBorder(slice)
    local definition = Ring_Kinds.Get(slice.kind)
    return definition ~= nil and definition.noIconBorder == true
end

--- What's drawn behind `slice`'s icon (its kind's underlay), or nil.
---@param slice Slice
---@return string? texture
---@return table? color { r, g, b }
function Ring_Actions.GetUnderlay(slice)
    local definition = Ring_Kinds.Get(slice.kind)
    if not (definition and definition.underlay) then return nil end
    return definition.underlay(slice)
end

--- The name `slice` shows. When its kind has none right now (an item the game hasn't loaded yet),
--- that's its identity, like "item:6948". An action of a kind this game doesn't have (another game
--- version's) shows its kind's name.
---@param slice Slice
---@return string
function Ring_Actions.GetLabel(slice)
    if slice.label then return slice.label end
    local definition = Ring_Kinds.Get(slice.kind)
    if not definition then return tostring(slice.kind) end
    return (definition.label and definition.label(slice)) or Ring_Data.GetSliceKey(slice)
end

--- What `slice`'s cooldown swipe follows: a spell, an item (items and toys) or an equipped slot.
---@param slice Slice
---@return string? source a Ring_Kinds.Source value
---@return (number|string)? id
function Ring_Actions.GetCooldownSource(slice)
    local definition = Ring_Kinds.Get(slice.kind)
    if definition and definition.cooldown then return definition.cooldown(slice) end
end

--- What `slice`'s icon state follows in the in-game menu (usable, in range, active): a spell, an
--- item or an equipped slot. Toys and the like have none, because they're always usable.
---@param slice Slice
---@return string? source a Ring_Kinds.Source value
---@return (number|string)? id a spell can be a name, when it's cast by name (Spell.lua)
function Ring_Actions.GetStateSource(slice)
    local definition = Ring_Kinds.Get(slice.kind)
    if definition and definition.state then return definition.state(slice) end
end

--- Shows `slice` in `tooltip` (already owned).
---@param tooltip GameTooltip
---@param slice Slice
---@return boolean handled false when the kind has nothing richer than a name
function Ring_Actions.SetTooltip(tooltip, slice)
    local definition = Ring_Kinds.Get(slice.kind)
    return (definition and definition.tooltip and definition.tooltip(tooltip, slice)) or false
end

-- Visibility. Actions that have nothing to fire are left out of the in-game menu (Ring_Secure
-- rebuilds the menus, after combat if needed, when this changes). The settings preview shows every
-- action, with a badge on the ones that can hide.

--- The key of `slice`'s visibility rule, for "Config - Rings - Visibility - <key>", or nil when it
--- always shows.
---@param slice Slice
---@return string?
function Ring_Actions.GetVisibilityCondition(slice)
    local definition = Ring_Kinds.Get(slice.kind)
    local condition = definition and definition.condition
    if type(condition) == "function" then return condition(slice) end
    return condition
end

--- Whether `slice` has something to fire right now. A kind that isn't registered (another game
--- version's, see Ring_Kinds.lua) has nothing, so its saved actions are hidden in game.
---@param slice Slice
---@param depth integer? how deep in submenus it's asked from
---@return boolean
function Ring_Actions.IsSliceAvailable(slice, depth)
    if not Ring_Kinds.Get(slice.kind) then return false end
    if not Ring_Actions.GetVisibilityCondition(slice) then return true end
    return Ring_Kinds.Get(slice.kind).available(slice, depth or 0)
end

-- Game state the secure attributes depend on

--- A value that changes whenever some kind's attributes would come out differently (like the zone
--- ability). Ring_Auto rebuilds the menus when it does and a menu has such an action.
---@return string signature
---@return table<string, boolean> kinds the kinds whose attributes depend on game state
function Ring_Actions.GetAttributeSignature()
    local parts, kinds = {}, {}
    for _, definition in ipairs(Ring_Kinds.All()) do
        if definition.attributesChangeWith then
            kinds[definition.kind] = true
            parts[#parts + 1] = definition.kind .. "=" .. tostring(definition.attributesChangeWith())
        end
    end
    return table.concat(parts, ";"), kinds
end
