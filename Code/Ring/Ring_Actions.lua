--[[
    What a slice does and shows: secure action button attributes, icon, label, cooldown source
    and visibility. The per-kind logic lives in the kind definitions (Ring_Kinds, Kinds\*.lua);
    this is the interface the rest of the addon uses.

    Optional on any slice:
        icon:   number|string icon override
        label:  string display name override
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Actions = env.AX_Modules:New("@\\Ring\\Actions")

local Get = Ring_Kinds.Get

-- Every secure attribute a kind may set. Cleared before applying a slice, so nothing is left over
-- from what this suffix held before a rebuild (another action, or another mode of the same one).
local SLICE_ATTRIBUTES = { "type", "spell", "item", "toy", "macro", "macrotext", "action", "marker", "unit", "clickbutton" }

--- Sets the attributes for `slice` under button suffix `suffix` ("*type-<suffix>", ...).
--- Must be called out of combat.
function Ring_Actions.ApplySliceSuffix(button, suffix, slice)
    for _, name in ipairs(SLICE_ATTRIBUTES) do
        Ring_Kinds.SetAttribute(button, name, suffix, nil)
    end
    local definition = Get(slice.kind)
    if definition and definition.apply then
        definition.apply(button, suffix, slice)
    else
        Ring_Kinds.ClearAction(button, suffix)
    end
end

--- Must be called out of combat.
function Ring_Actions.ApplySlice(button, index, slice)
    Ring_Actions.ApplySliceSuffix(button, "s" .. index, slice)
end

function Ring_Actions.GetIcon(slice, depth)
    if slice.icon then return slice.icon end
    local definition = Get(slice.kind)
    return definition and definition.icon and definition.icon(slice, depth or 0) or Ring_Kinds.QUESTION_MARK_ICON
end

function Ring_Actions.GetLabel(slice)
    if slice.label then return slice.label end
    local definition = Get(slice.kind)
    return definition and definition.label and definition.label(slice) or tostring(slice.kind)
end

--- What a slice's cooldown swipe follows: a spell, an item (items and toys) or an equipped slot.
--- @return string|nil kind "spell" | "item" | "inventory"
--- @return number|nil id
function Ring_Actions.GetCooldownSource(slice)
    local definition = Get(slice.kind)
    if definition and definition.cooldown then return definition.cooldown(slice) end
end

--- Shows `slice` in `tooltip` (already owned); false when the kind has nothing richer than a name.
function Ring_Actions.SetTooltip(tooltip, slice)
    local definition = Get(slice.kind)
    return definition and definition.tooltip and definition.tooltip(tooltip, slice) or false
end



-- Visibility: slices that have nothing to fire are left out of the in-game ring (Ring_Secure
-- rebuilds the rings, after combat if needed, when this changes). The settings preview shows
-- every slice, with a badge on the ones that can hide.

--- @return string|nil key of the visibility rule, for "Config - Rings - Visibility - <key>"
function Ring_Actions.GetVisibilityCondition(slice)
    local definition = Get(slice.kind)
    local condition = definition and definition.condition
    if type(condition) == "function" then return condition(slice) end
    return condition
end

--- A kind that isn't registered (another game version's, see Ring_Kinds.lua) has nothing to
--- fire: its saved actions are hidden in game.
function Ring_Actions.IsSliceAvailable(slice, depth)
    if not Get(slice.kind) then return false end
    if not Ring_Actions.GetVisibilityCondition(slice) then return true end
    return Get(slice.kind).available(slice, depth or 0)
end



-- Game state the secure attributes depend on

--- A value that changes whenever some kind's attributes would come out differently (e.g. the
--- zone ability): Ring_Auto rebuilds the rings when it does and a menu has such a slice.
--- @return string signature, table kinds set of kinds whose attributes depend on game state
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
