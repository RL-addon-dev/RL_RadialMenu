--[[
    What an action does and shows: its secure action button attributes, icon, label, cooldown
    source and visibility. The per-kind logic lives in the kind definitions (Menu_Kinds,
    Kinds\*.lua), and this is the interface the rest of the addon uses.

    Any action can override how it's shown.
        icon    an icon (number or path) instead of its kind's
        label   a name instead of its kind's
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Actions = env.AX_Modules:New("@\\Menu\\Actions")

-- Every secure attribute a kind may set. They're cleared before applying an action, so nothing is
-- left over from what this suffix held before a rebuild (another action, or another mode of the
-- same one).
local ACTION_ATTRIBUTES = {
    -- The game's own.
    "type", "spell", "item", "toy", "macro", "macrotext", "action", "marker", "unit", "clickbutton",
    -- The addon's own (Menu_Kinds.ActionAttribute).
    Menu_Kinds.ActionAttribute.PagedButton, Menu_Kinds.ActionAttribute.Close,
    Menu_Kinds.ActionAttribute.LastUsed, Menu_Kinds.ActionAttribute.First,
}

--- Sets the attributes for `action` under button suffix `suffix` ("*type-<suffix>", ...). Call it
--- out of combat.
---@param button Button
---@param suffix string
---@param action Action
function Menu_Actions.ApplyActionSuffix(button, suffix, action)
    for _, name in ipairs(ACTION_ATTRIBUTES) do
        Menu_Kinds.SetSlotAttribute(button, name, suffix, nil)
    end
    local definition = Menu_Kinds.Get(action.kind)
    if definition and definition.apply then
        definition.apply(button, suffix, action)
    else
        Menu_Kinds.ClearAction(button, suffix)
    end
end

--- Sets the attributes for `action` as the menu button's action `index`. Call it out of combat.
---@param button Button
---@param index integer
---@param action Action
function Menu_Actions.ApplyAction(button, index, action)
    Menu_Actions.ApplyActionSuffix(button, "s" .. index, action)
end

--- The icon `action` shows, or the question mark when its kind has none right now.
---@param action Action
---@param depth integer? how deep in submenus it's asked from (submenus show a child's icon)
---@return number|string
function Menu_Actions.GetIcon(action, depth)
    if action.icon then return action.icon end
    local definition = Menu_Kinds.Get(action.kind)
    return (definition and definition.icon and definition.icon(action, depth or 0)) or Menu_Kinds.QUESTION_MARK_ICON
end

--- Whether `action`'s icon is shown without the action button border (its kind's noIconBorder).
---@param action Action
---@return boolean
function Menu_Actions.HasNoIconBorder(action)
    local definition = Menu_Kinds.Get(action.kind)
    return definition ~= nil and definition.noIconBorder == true
end

--- What's drawn behind `action`'s icon (its kind's underlay), or nil.
---@param action Action
---@return string? texture
---@return table? color { r, g, b }
function Menu_Actions.GetUnderlay(action)
    local definition = Menu_Kinds.Get(action.kind)
    if not (definition and definition.underlay) then return nil end
    return definition.underlay(action)
end

--- The name `action` shows. When its kind has none right now (an item the game hasn't loaded yet),
--- that's its identity, like "item:6948". An action of a kind this game doesn't have (another game
--- version's) shows its kind's name.
---@param action Action
---@return string
function Menu_Actions.GetLabel(action)
    if action.label then return action.label end
    local definition = Menu_Kinds.Get(action.kind)
    if not definition then return tostring(action.kind) end
    return (definition.label and definition.label(action)) or Menu_Data.GetActionKey(action)
end

--- What `action`'s cooldown swipe follows: a spell, an item (items and toys) or an equipped slot.
---@param action Action
---@return string? source a Menu_Kinds.Source value
---@return (number|string)? id
function Menu_Actions.GetCooldownSource(action)
    local definition = Menu_Kinds.Get(action.kind)
    if definition and definition.cooldown then return definition.cooldown(action) end
end

--- What `action`'s icon state follows in the in-game menu (usable, in range, active): a spell, an
--- item or an equipped slot. Toys and the like have none, because they're always usable.
---@param action Action
---@return string? source a Menu_Kinds.Source value
---@return (number|string)? id a spell can be a name, when it's cast by name (Spell.lua)
function Menu_Actions.GetStateSource(action)
    local definition = Menu_Kinds.Get(action.kind)
    if definition and definition.state then return definition.state(action) end
end

--- Shows `action` in `tooltip` (already owned).
---@param tooltip GameTooltip
---@param action Action
---@return boolean handled false when the kind has nothing richer than a name
function Menu_Actions.SetTooltip(tooltip, action)
    local definition = Menu_Kinds.Get(action.kind)
    return (definition and definition.tooltip and definition.tooltip(tooltip, action)) or false
end

-- Visibility. Actions that have nothing to fire are left out of the in-game menu (Menu_Secure
-- rebuilds the menus, after combat if needed, when this changes). The settings preview shows every
-- action, with a badge on the ones that can hide.

--- The key of `action`'s visibility rule, for "Config - Menus - Visibility - <key>", or nil when it
--- always shows.
---@param action Action
---@return string?
function Menu_Actions.GetVisibilityCondition(action)
    local definition = Menu_Kinds.Get(action.kind)
    local condition = definition and definition.condition
    if type(condition) == "function" then return condition(action) end
    return condition
end

--- Whether `action` has something to fire right now. A kind that isn't registered (another game
--- version's, see Menu_Kinds.lua) has nothing, so its saved actions are hidden in game.
---@param action Action
---@param depth integer? how deep in submenus it's asked from
---@return boolean
function Menu_Actions.IsActionAvailable(action, depth)
    if not Menu_Kinds.Get(action.kind) then return false end
    if not Menu_Actions.GetVisibilityCondition(action) then return true end
    return Menu_Kinds.Get(action.kind).available(action, depth or 0)
end

-- Game state the secure attributes depend on

--- A value that changes whenever some kind's attributes would come out differently (like the zone
--- ability). Menu_Auto rebuilds the menus when it does and a menu has such an action.
---@return string signature
---@return table<string, boolean> kinds the kinds whose attributes depend on game state
function Menu_Actions.GetAttributeSignature()
    local parts, kinds = {}, {}
    for _, definition in ipairs(Menu_Kinds.All()) do
        if definition.attributesChangeWith then
            kinds[definition.kind] = true
            parts[#parts + 1] = definition.kind .. "=" .. tostring(definition.attributesChangeWith())
        end
    end
    return table.concat(parts, ";"), kinds
end
