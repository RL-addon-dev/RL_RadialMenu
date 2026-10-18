--[[
    Ring data: sharing menus as text (Import and Share in the Menus tab). It's used like this:

        local text, summary = Ring_Data.BuildShare({ ringId, ... })   -- the ticked menus
        local plan, reason, header = Ring_Data.ReadShare(text)          -- nothing changes yet
        local ok, reason = Ring_Data.ApplyShare(plan, Ring_Data.Scope.Account)

    A share holds the ticked menus and every submenu they contain. A built-in submenu travels as
    its key only, because it fills itself, and on import it links to the importer's own built-in
    menu. Keybinds, scope and a submenu's spread or scroll setting aren't shared. The string is
    made by ax_modules\\share-string, with the header { addon = "RLRM", version, game }, and only
    strings of this game import.

    The payload (FORMAT_VERSION 1) has two parts.
        menus   an array of { name, slices, quickAction = "custom", quickSlice }. A submenu action
                is { kind = "ring", ring = <index in menus> }, or { kind = "ring", builtin = <key> }
                for a built-in one. Older strings' quickAction (an index into slices, or "last") is
                ignored, so the menu imports without one.
        macros  [name] = { icon, body }, for the macro actions

    Each action kind decides how it travels (Ring_Kinds `share`). By default it travels as it is,
    checked by its `validate` on import. Macros carry their text and are created on import (as
    account macros). Battle pets don't travel, because a pet belongs to its account, except a
    random favorite.

    ReadShare builds a plan with the menus' final names ("Name (2)" on a clash), the macros it will
    create, and what it skipped and why (Ring_Data.ShareSkip). The Import page shows it, and
    ApplyShare carries it out. Nothing from the string is ever run, but a new macro can be, so the
    page shows its text before importing.
]]

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local ShareString = env.AX_Modules:Import("ax_modules\\share-string")
local Utils_General = env.AX_Modules:Import("ax_modules\\utils\\general")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")

local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring

local ADDON = "RLRM"
local FORMAT_VERSION = 1
local MAX_MENUS = 50
local MAX_SLICES = 64          -- per menu
local MAX_MENU_NAME = 64       -- bytes
local MAX_MACRO_NAME = 16      -- the game's limit
local MAX_MACRO_BODY = 255     -- the game's limit
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120

-- Why an action was left out, counted per reason in a share summary or an import plan.
Ring_Data.ShareSkip = Utils_Standard.Strict({
    BattlePet    = "battlepet",     -- a pet belongs to the account that has it
    BuiltIn      = "builtin",       -- when importing, a built-in submenu this game doesn't have
    MissingMacro = "missing-macro", -- when sharing, the macro no longer exists
    MacroSlots   = "macro-slots",   -- when importing, no free account macro slots
    Invalid      = "invalid",       -- not an action of this game, or it failed its checks
    Empty        = "empty",         -- when sharing, a submenu with nothing left in it
}, "share skip reason")

-- Why a whole import was refused (besides ShareString.Error, for a string it can't read).
Ring_Data.ShareError = Utils_Standard.Strict({
    Combat  = "combat",  -- macros (and menus) aren't created in combat
    Nothing = "nothing", -- every menu in the string ends up empty
}, "share error")

-- BreakLoops' marks while it walks the submenus.
local VISITING, VISITED = 1, 2

--- Counts one more action left out for `reason`.
---@param skipped table<string, integer> counts by Ring_Data.ShareSkip reason
---@param reason string? Invalid when nil
local function CountSkip(skipped, reason)
    reason = reason or Ring_Data.ShareSkip.Invalid
    skipped[reason] = (skipped[reason] or 0) + 1
end

--- Drops the menus with nothing in them (no actions and no quick action) and the submenu links
--- to them. That can empty more menus, so it repeats, then renumbers the links. It works on shared
--- menus and on a plan's, which both link a submenu as { kind = "ring", ring = <index> }.
---@param menus table[]
---@return table[] kept the menus left, in order
---@return table<integer, boolean> dropped the old indexes of the dropped menus
local function DropEmptyMenus(menus)
    local dropped = {}
    repeat
        local changed = false
        for index, menu in ipairs(menus) do
            if not dropped[index] and #menu.slices == 0 and not menu.quickSlice then
                dropped[index], changed = true, true
            end
        end
        for index, menu in ipairs(menus) do
            if changed and not dropped[index] then
                for i = #menu.slices, 1, -1 do
                    local slice = menu.slices[i]
                    if slice.kind == Ring_Kinds.Kind.Ring and not slice.builtin and dropped[slice.ring] then
                        table.remove(menu.slices, i)
                        if menu.skipped then CountSkip(menu.skipped, Ring_Data.ShareSkip.Empty) end -- an import's menu
                    end
                end
            end
        end
    until not changed

    local kept, newIndex = {}, {}
    for index, menu in ipairs(menus) do
        if not dropped[index] then
            kept[#kept + 1] = menu
            newIndex[index] = #kept
        end
    end
    for _, menu in ipairs(kept) do
        for _, slice in ipairs(menu.slices) do
            if slice.kind == Ring_Kinds.Kind.Ring and not slice.builtin then slice.ring = newIndex[slice.ring] end
        end
    end
    return kept, dropped
end

-- Share

--- What travels for `slice`, from its kind's `share.pack` or else a copy. Nil and a reason when
--- it's left out.
---@param slice Slice
---@param macros table the share's macros, which `share.pack` adds to
---@return Slice? packed
---@return string? reason a Ring_Data.ShareSkip value
local function PackSlice(slice, macros)
    local definition = Ring_Kinds.Get(slice.kind)
    if not definition then return nil, Ring_Data.ShareSkip.Invalid end
    if definition.share and definition.share.pack then return definition.share.pack(slice, macros) end
    return CopyTable(slice)
end

--- Builds a share string from the ticked menus, adding their submenus.
---@param ringIds (string|number)[] the ticked menus' ids
---@return string text "" when nothing's left to share (every menu is empty)
---@return table summary { submenus, macros, skippedNames }. `submenus` lists the shared
---     submenus' names, `macros` the macros whose text travels too, and `skippedNames` what was
---     left out ({ [Ring_Data.ShareSkip] = { label, ... } }).
function Ring_Data.BuildShare(ringIds)
    -- The ticked menus, then every submenu they reach (depth first), each once. Any of them can
    -- live elsewhere (another class's or character's, Elsewhere.lua). Those are shared from their
    -- saved copy, so a menu travels whole wherever its submenus live.
    local rings, indexOf = {}, {}
    local function Add(id)
        local ring = Ring_Data.GetRing(id) or (Ring_Data.GetElsewhereRing(id))
        if not ring or Ring_Data.IsBuiltIn(ring) or indexOf[ring.id] then return end
        rings[#rings + 1] = ring
        indexOf[ring.id] = #rings
        for _, slice in ipairs(ring.slices) do
            if slice.kind == Ring_Kinds.Kind.Ring then Add(slice.ring) end
        end
    end
    for _, id in ipairs(ringIds) do Add(id) end

    local menus, macros, skippedNames = {}, {}, {}
    -- What's left out, by reason, each name once. The Share box lists it.
    local function AddSkip(reason, label)
        reason = reason or Ring_Data.ShareSkip.Invalid
        local names = skippedNames[reason] or {}
        skippedNames[reason] = names
        if not tContains(names, label) then names[#names + 1] = label end
    end
    for menuIndex, ring in ipairs(rings) do
        local menu, newIndex = { name = ring.name, slices = {} }, {}
        for index, slice in ipairs(ring.slices) do
            local packed, reason
            -- A submenu found nowhere is left out, and not listed as skipped. That's one with no
            -- saved copy, from a character that hasn't logged in since.
            local child = slice.kind == Ring_Kinds.Kind.Ring and indexOf[tostring(slice.ring)]
            local elsewhere = not child and Ring_Data.IsElsewhere(slice)
            if elsewhere then
                packed = nil
            elseif slice.kind == Ring_Kinds.Kind.Ring then
                local childRing = not child and Ring_Data.GetRing(slice.ring)
                if child then
                    packed = { kind = Ring_Kinds.Kind.Ring, ring = child }
                elseif childRing and Ring_Data.IsBuiltIn(childRing) then
                    packed = { kind = Ring_Kinds.Kind.Ring, builtin = childRing.builtin }
                else
                    reason = Ring_Data.ShareSkip.Invalid
                end
            else
                packed, reason = PackSlice(slice, macros)
            end
            if packed then
                packed.expand = nil
                menu.slices[#menu.slices + 1] = packed
                newIndex[index] = #menu.slices
            elseif not elsewhere then
                AddSkip(reason, Ring_Actions.GetLabel(slice))
            end
        end

        local center = Ring_Data.GetQuickActionSlice(ring)
        if center then
            local packed, reason = PackSlice(center, macros)
            if packed then
                menu.quickAction, menu.quickSlice = Ring_Data.QuickAction.Custom, packed
            else
                AddSkip(reason, Ring_Actions.GetLabel(center))
            end
        end
        menus[menuIndex] = menu
    end

    -- Menus with nothing left in them aren't shared, and neither are the links to them. A dropped
    -- submenu is listed as Empty. An empty menu that was ticked leaves nothing to share.
    local roots = {}
    for _, id in ipairs(ringIds) do
        if indexOf[tostring(id)] then roots[indexOf[tostring(id)]] = true end
    end
    local kept, dropped = DropEmptyMenus(menus)
    local submenus = {}
    for index, ring in ipairs(rings) do
        if dropped[index] then
            if not roots[index] then AddSkip(Ring_Data.ShareSkip.Empty, ring.name) end
        elseif not roots[index] then
            submenus[#submenus + 1] = ring.name
        end
    end

    local macroNames = {}
    for name in pairs(macros) do macroNames[#macroNames + 1] = name end
    table.sort(macroNames)
    local summary = { submenus = submenus, macros = macroNames, skippedNames = skippedNames }
    if #kept == 0 then return "", summary end
    local header = { addon = ADDON, version = FORMAT_VERSION, game = env.GAME_VERSION }
    return ShareString.Encode(header, { menus = kept, macros = macros }), summary
end

-- Import: the plan

local PlanMixin = {}

--- The name a macro action's macro will have after the import, for kinds' `share.unpack`. The
--- same macro (name and text) already there is used. Otherwise one is created, as "Name (2)" when
--- the name is taken. Nil and a reason when there's no room, or no such macro in the string.
---@param name string the macro's name in the string
---@return string? name
---@return string? reason a Ring_Data.ShareSkip value
function PlanMixin:ResolveMacro(name)
    if self.macroNames[name] then return self.macroNames[name] end
    local data = type(name) == "string" and self.macroData[name]
    if type(data) ~= "table" or type(data.body) ~= "string" or #data.body > MAX_MACRO_BODY then
        return nil, Ring_Data.ShareSkip.Invalid
    end

    local existing = GetMacroIndexByName(name)
    if existing and existing > 0 and select(3, GetMacroInfo(existing)) == data.body then
        self.macroNames[name] = name
        return name
    end

    local accountMacros = GetNumMacros()
    if accountMacros + #self.macros >= MAX_ACCOUNT_MACROS then return nil, Ring_Data.ShareSkip.MacroSlots end

    local newName = Utils_General.GetUniqueName(name, function(candidate)
        local index = GetMacroIndexByName(candidate)
        return (index and index > 0) or self.reservedMacros[candidate] ~= nil
    end, MAX_MACRO_NAME)
    self.reservedMacros[newName] = true
    self.macros[#self.macros + 1] = {
        name = newName, sourceName = name, body = data.body,
        icon = ((type(data.icon) == "number" or type(data.icon) == "string") and data.icon) or Ring_Kinds.QUESTION_MARK_ICON,
    }
    self.macroNames[name] = newName
    return newName
end

--- An action from the string as it will be saved, through its kind's `share.unpack` and then its
--- `validate`. ReadShare handles submenus. Nil and a reason when it's skipped.
---@param slice any
---@return Slice? slice
---@return string? reason a Ring_Data.ShareSkip value
function PlanMixin:UnpackSlice(slice)
    if type(slice) ~= "table" or type(slice.kind) ~= "string" or slice.kind == Ring_Kinds.Kind.Ring then
        return nil, Ring_Data.ShareSkip.Invalid
    end
    local definition = Ring_Kinds.Get(slice.kind)
    if not definition then return nil, Ring_Data.ShareSkip.Invalid end -- another game's kind
    local unpacked, reason = CopyTable(slice), nil
    if definition.share and definition.share.unpack then
        unpacked, reason = definition.share.unpack(unpacked, self)
        if not unpacked then return nil, reason end
    end
    if not Ring_Data.ValidateSlice(nil, unpacked) then return nil, Ring_Data.ShareSkip.Invalid end
    return unpacked
end

--- Drops submenu actions that would make menus contain each other in a loop.
---@param entries table[] the plan's menus
local function BreakLoops(entries)
    local state = {} -- [index] = VISITING or VISITED
    local function Visit(index)
        state[index] = VISITING
        local entry = entries[index]
        for i = #entry.slices, 1, -1 do
            local slice = entry.slices[i]
            if slice.kind == Ring_Kinds.Kind.Ring and not slice.builtin then -- built-ins hold no submenus
                if state[slice.ring] == VISITING then
                    table.remove(entry.slices, i)
                    CountSkip(entry.skipped, Ring_Data.ShareSkip.Invalid)
                elseif not state[slice.ring] then
                    Visit(slice.ring)
                end
            end
        end
        state[index] = VISITED
    end
    for index in ipairs(entries) do
        if not state[index] then Visit(index) end
    end
end

--- Reads a share string into an import plan. Nothing changes until ApplyShare.
---
--- The plan has `menus`, each { name, sourceName, slices, quickAction, quickSlice, parent?,
--- skipped }, where `skipped` counts what was left out by Ring_Data.ShareSkip reason. It also has
--- `macros` to create, each { name, sourceName, body, icon }.
---@param text string
---@return table? plan
---@return string? reason a ShareString.Error, or Ring_Data.ShareError.Nothing, when refused
---@return table? header when refused after the header could be read (header.game is the other game)
function Ring_Data.ReadShare(text)
    local payload, headerOrError, refusedHeader = ShareString.Decode(text, {
        addon = ADDON, maxVersion = FORMAT_VERSION, game = env.GAME_VERSION,
    })
    if not payload then return nil, headerOrError, refusedHeader end
    local menus = type(payload) == "table" and payload.menus
    if type(menus) ~= "table" or #menus == 0 or #menus > MAX_MENUS then return nil, ShareString.Error.Invalid end

    local plan = CreateFromMixins(PlanMixin)
    plan.menus, plan.macros = {}, {}
    plan.macroData = type(payload.macros) == "table" and payload.macros or {}
    plan.macroNames, plan.reservedMacros = {}, {}

    for menuIndex, menu in ipairs(menus) do
        if type(menu) ~= "table" or type(menu.slices) ~= "table" or #menu.slices > MAX_SLICES then
            return nil, ShareString.Error.Invalid
        end
        local sourceName = type(menu.name) == "string" and strtrim(menu.name) or ""
        if sourceName == "" then sourceName = L["Config - Rings - NewRing - DefaultName"] end

        local entry = { sourceName = sourceName, slices = {}, skipped = {} }
        for _, slice in ipairs(menu.slices) do
            local unpacked, reason
            if type(slice) == "table" and slice.kind == Ring_Kinds.Kind.Ring then
                local child = slice.ring
                local builtIn = type(slice.builtin) == "string" and Ring_Data.GetBuiltInRing(slice.builtin)
                if type(child) == "number" and menus[child] and child ~= menuIndex then
                    unpacked = { kind = Ring_Kinds.Kind.Ring, ring = child }
                elseif builtIn then
                    -- This character's own built-in menu, linked by its saved id (not an index).
                    unpacked = { kind = Ring_Kinds.Kind.Ring, ring = builtIn.id, builtin = true }
                else
                    reason = (type(slice.builtin) == "string" and Ring_Data.ShareSkip.BuiltIn)
                        or Ring_Data.ShareSkip.Invalid
                end
            else
                unpacked, reason = plan:UnpackSlice(slice)
            end
            if unpacked then
                entry.slices[#entry.slices + 1] = unpacked
            else
                CountSkip(entry.skipped, reason)
            end
        end

        if menu.quickAction == Ring_Data.QuickAction.Custom then
            local quickSlice, reason = plan:UnpackSlice(menu.quickSlice)
            if quickSlice then
                entry.quickAction, entry.quickSlice = Ring_Data.QuickAction.Custom, quickSlice
            else
                CountSkip(entry.skipped, reason)
            end
        end
        plan.menus[menuIndex] = entry
    end

    BreakLoops(plan.menus)
    -- A menu with nothing left in it (all its actions skipped) isn't created.
    plan.menus = DropEmptyMenus(plan.menus)
    if #plan.menus == 0 then return nil, Ring_Data.ShareError.Nothing end

    local takenNames = {}
    for _, ring in ipairs(Ring_Data.GetRings()) do takenNames[ring.name] = true end
    for _, entry in ipairs(plan.menus) do
        entry.name = Utils_General.GetUniqueName(entry.sourceName, function(candidate) return takenNames[candidate] end, MAX_MENU_NAME)
        takenNames[entry.name] = true
    end

    -- Each submenu is shown under the first menu found that contains it.
    for index, entry in ipairs(plan.menus) do
        for _, slice in ipairs(entry.slices) do
            if slice.kind == Ring_Kinds.Kind.Ring and not slice.builtin and not plan.menus[slice.ring].parent then
                plan.menus[slice.ring].parent = index
            end
        end
    end
    return plan
end

-- Import: carrying it out

--- Creates the plan's macros and menus in `scope`. They're all new, nothing is replaced.
---@param plan table from Ring_Data.ReadShare
---@param scope string a Ring_Data.Scope value
---@return boolean ok
---@return string|Ring[] reasonOrRings a Ring_Data.ShareError value, or the menus created in plan order
function Ring_Data.ApplyShare(plan, scope)
    if InCombatLockdown() then return false, Ring_Data.ShareError.Combat end

    for _, macro in ipairs(plan.macros) do
        CreateMacro(macro.name, macro.icon, macro.body, false) -- account macro
    end

    -- Every menu first, so submenu actions can point at their new ids.
    local rings = {}
    for index, entry in ipairs(plan.menus) do
        rings[index] = Ring_Data.CreateRing(entry.name, scope)
    end
    for index, entry in ipairs(plan.menus) do
        local ring = rings[index]
        ring.slices = {}
        for _, slice in ipairs(entry.slices) do
            local stored = CopyTable(slice)
            if stored.kind == Ring_Kinds.Kind.Ring then
                if stored.builtin then stored.builtin = nil else stored.ring = rings[stored.ring].id end
            end
            ring.slices[#ring.slices + 1] = stored
        end
        ring.quickAction = entry.quickAction or Ring_Data.QuickAction.None
        ring.quickSlice = entry.quickSlice and CopyTable(entry.quickSlice) or nil
        Private.NormalizeRing(ring)
    end
    Private.Changed()
    return true, rings
end
