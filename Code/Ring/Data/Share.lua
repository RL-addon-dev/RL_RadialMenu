--[[
    Ring data: sharing menus as text (Import / Share in the Menus tab).

        local text, summary = Ring_Data.BuildShare({ ringId, ... })   -- ticked menus
        local plan, reason, header = Ring_Data.ReadShare(text)          -- nothing changes yet
        local ok, reason = Ring_Data.ApplyShare(plan, Ring_Data.Scope.Account)

    A share holds the ticked menus and every submenu they contain. A built-in submenu travels
    as its key only (it fills itself): on import it links to the importer's own built-in menu.
    Not shared: keybinds, scope, a submenu's spread / scroll mode. The string is
    ax_modules\\share-string's, header { addon = "RLRM", version, game }: only strings of this
    game import.

    Payload (FORMAT_VERSION 1):
        menus   array of { name, slices, quickAction = "custom", quickSlice }
                (older strings' quickAction, an index into slices or "last", is ignored: the menu
                imports without one)
                a submenu slice is { kind = "ring", ring = <index in menus> }, or for a
                built-in one { kind = "ring", builtin = <key> }
        macros  [name] = { icon, body }, for the macro actions

    Each action kind decides how it travels (Ring_Kinds `share`): by default as it is, checked
    by its `validate` on import. Macros carry their text and are created on import (account
    macros); battle pets don't travel (a pet belongs to its account) except a random favorite.

    ReadShare builds a plan: the menus with their final names ("Name (2)" on a clash), the
    macros it will create, and what it skipped and why (Ring_Data.ShareSkip). The Import page
    shows it; ApplyShare carries it out. Nothing from the string is ever run, but a new macro
    can be: the page shows its text before importing.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")
local Ring_Kinds = env.AX_Modules:Await("@\\Ring\\Kinds")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local ShareString = env.AX_Modules:Import("ax_modules\\share-string")
local Utils_General = env.AX_Modules:Import("ax_modules\\utils\\general")

local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring

local ADDON = "RLRM"
local FORMAT_VERSION = 1
local MAX_MENUS = 50
local MAX_SLICES = 64          -- per menu
local MAX_MENU_NAME = 64       -- bytes
local MAX_MACRO_NAME = 16      -- the game's limit
local MAX_MACRO_BODY = 255     -- the game's limit
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120

--- Why an action was left out (counted per reason in a share summary or an import plan).
Ring_Data.ShareSkip = {
    BattlePet    = "battlepet",     -- a pet belongs to the account that has it
    BuiltIn      = "builtin",       -- importing: a built-in submenu this game doesn't have
    MissingMacro = "missing-macro", -- sharing: the macro no longer exists
    MacroSlots   = "macro-slots",   -- importing: no free account macro slots
    Invalid      = "invalid",       -- not an action of this game, or failed its checks
    Empty        = "empty",         -- sharing: a submenu with nothing left in it
}
local Skip = Ring_Data.ShareSkip

local function CountSkip(skipped, reason)
    reason = reason or Skip.Invalid
    skipped[reason] = (skipped[reason] or 0) + 1
end

--- Drops the menus with nothing in them (no actions, no tap-only quick action) and the
--- submenu links to them, again while that empties a menu, then renumbers the links. Works on
--- shared menus and on a plan's (both link a submenu as { kind = "ring", ring = <index> }).
--- @return table kept the menus left, in order
--- @return table dropped { [old index] = true }
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
                    if slice.kind == "ring" and not slice.builtin and dropped[slice.ring] then
                        table.remove(menu.slices, i)
                        if menu.skipped then CountSkip(menu.skipped, Skip.Empty) end -- an import's menu
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
            if slice.kind == "ring" and not slice.builtin then slice.ring = newIndex[slice.ring] end
        end
    end
    return kept, dropped
end



-- Share

--- What travels for `slice`: its kind's `share.pack`, else a copy (nil, reason: left out).
local function PackSlice(slice, macros)
    local definition = Ring_Kinds.Get(slice.kind)
    if not definition then return nil, Skip.Invalid end
    if definition.share and definition.share.pack then return definition.share.pack(slice, macros) end
    return CopyTable(slice)
end

--- @param ringIds table the ticked menus' ids; their submenus are added
--- @return string text "" when nothing's left to share (every menu empty)
--- @return table summary { submenus = { name, ... } (the shared ones), macros = { name, ... }
---     (their text travels too), skippedNames = { [reason] = { label, ... } } (left out) }
function Ring_Data.BuildShare(ringIds)
    -- The ticked menus, then every submenu they reach (depth first), each once.
    local rings, indexOf = {}, {}
    local function Add(id)
        local ring = Ring_Data.GetRing(id)
        if not ring or Ring_Data.IsBuiltIn(ring) or indexOf[ring.id] then return end
        rings[#rings + 1] = ring
        indexOf[ring.id] = #rings
        for _, slice in ipairs(ring.slices) do
            if slice.kind == "ring" then Add(slice.ring) end
        end
    end
    for _, id in ipairs(ringIds) do Add(id) end

    local menus, macros, skippedNames = {}, {}, {}
    -- What's left out, by reason (the Share box lists it), each name once.
    local function AddSkip(reason, label)
        reason = reason or Skip.Invalid
        local names = skippedNames[reason] or {}
        skippedNames[reason] = names
        if not tContains(names, label) then names[#names + 1] = label end
    end
    for menuIndex, ring in ipairs(rings) do
        local menu, newIndex = { name = ring.name, slices = {} }, {}
        for index, slice in ipairs(ring.slices) do
            local packed, reason
            if slice.kind == "ring" then
                local child = indexOf[tostring(slice.ring)]
                local childRing = not child and Ring_Data.GetRing(slice.ring)
                if child then
                    packed = { kind = "ring", ring = child }
                elseif childRing and Ring_Data.IsBuiltIn(childRing) then
                    packed = { kind = "ring", builtin = childRing.builtin }
                else
                    reason = Skip.Invalid
                end
            else
                packed, reason = PackSlice(slice, macros)
            end
            if packed then
                packed.expand = nil
                menu.slices[#menu.slices + 1] = packed
                newIndex[index] = #menu.slices
            else
                AddSkip(reason, Ring_Actions.GetLabel(slice))
            end
        end

        local center = Ring_Data.GetQuickActionSlice(ring)
        if center then
            local packed, reason = PackSlice(center, macros)
            if packed then
                menu.quickAction, menu.quickSlice = "custom", packed
            else
                AddSkip(reason, Ring_Actions.GetLabel(center))
            end
        end
        menus[menuIndex] = menu
    end

    -- Menus with nothing left in them aren't shared, nor the links to them. A dropped submenu
    -- is listed (Empty); an empty menu that was asked for leaves nothing to share.
    local roots = {}
    for _, id in ipairs(ringIds) do
        if indexOf[tostring(id)] then roots[indexOf[tostring(id)]] = true end
    end
    local kept, dropped = DropEmptyMenus(menus)
    local submenus = {}
    for index, ring in ipairs(rings) do
        if dropped[index] then
            if not roots[index] then AddSkip(Skip.Empty, ring.name) end
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

--- A macro action's macro (kinds' `share.unpack`): the name it will have after the import.
--- The same macro (name and text) already there is used; else one is created, as "Name (2)"
--- when the name is taken. Nil, reason when there's no room or no such macro in the string.
--- @return string|nil name
--- @return string|nil reason Ring_Data.ShareSkip
function PlanMixin:ResolveMacro(name)
    if self.macroNames[name] then return self.macroNames[name] end
    local data = type(name) == "string" and self.macroData[name]
    if type(data) ~= "table" or type(data.body) ~= "string" or #data.body > MAX_MACRO_BODY then
        return nil, Skip.Invalid
    end

    local existing = GetMacroIndexByName(name)
    if existing and existing > 0 and select(3, GetMacroInfo(existing)) == data.body then
        self.macroNames[name] = name
        return name
    end

    local accountMacros = GetNumMacros()
    if accountMacros + #self.macros >= MAX_ACCOUNT_MACROS then return nil, Skip.MacroSlots end

    local newName = Utils_General.GetUniqueName(name, function(candidate)
        local index = GetMacroIndexByName(candidate)
        return (index and index > 0) or self.reservedMacros[candidate] ~= nil
    end, MAX_MACRO_NAME)
    self.reservedMacros[newName] = true
    self.macros[#self.macros + 1] = {
        name = newName, sourceName = name, body = data.body,
        icon = (type(data.icon) == "number" or type(data.icon) == "string") and data.icon or 134400,
    }
    self.macroNames[name] = newName
    return newName
end

--- An action from the string as it will be stored: its kind's `share.unpack`, then its
--- `validate`. Submenus are handled by ReadShare. Nil, reason: skipped.
function PlanMixin:UnpackSlice(slice)
    if type(slice) ~= "table" or type(slice.kind) ~= "string" or slice.kind == "ring" then return nil, Skip.Invalid end
    local definition = Ring_Kinds.Get(slice.kind)
    if not definition then return nil, Skip.Invalid end -- another game's kind
    local unpacked, reason = CopyTable(slice), nil
    if definition.share and definition.share.unpack then
        unpacked, reason = definition.share.unpack(unpacked, self)
        if not unpacked then return nil, reason end
    end
    if not Ring_Data.ValidateSlice(nil, unpacked) then return nil, Skip.Invalid end
    return unpacked
end

--- Drops submenu slices that would make menus contain each other in a loop.
local function BreakLoops(entries)
    local state = {} -- index -> "visiting" | "done"
    local function Visit(index)
        state[index] = "visiting"
        local entry = entries[index]
        for i = #entry.slices, 1, -1 do
            local slice = entry.slices[i]
            if slice.kind == "ring" and not slice.builtin then -- built-ins hold no submenus
                if state[slice.ring] == "visiting" then
                    table.remove(entry.slices, i)
                    CountSkip(entry.skipped, Skip.Invalid)
                elseif not state[slice.ring] then
                    Visit(slice.ring)
                end
            end
        end
        state[index] = "done"
    end
    for index in ipairs(entries) do
        if not state[index] then Visit(index) end
    end
end

--- Reads a share string into an import plan. Nothing changes until ApplyShare.
--- @return table|nil plan {
---     menus   = { { name, sourceName, slices, quickAction, quickSlice, parent = index?,
---                   skipped = { [Ring_Data.ShareSkip] = count } }, ... },
---     macros  = { { name, sourceName, body, icon }, ... } }  -- to create
--- @return string|nil reason a ShareString.Error, or Ring_Data.ShareError.Nothing, when refused
--- @return table|nil header when refused after it could be read (header.game: the other game)
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
        if sourceName == "" then sourceName = "Menu" end

        local entry = { sourceName = sourceName, slices = {}, skipped = {} }
        for _, slice in ipairs(menu.slices) do
            local unpacked, reason
            if type(slice) == "table" and slice.kind == "ring" then
                local child = slice.ring
                local builtIn = type(slice.builtin) == "string" and Ring_Data.GetBuiltInRing(slice.builtin)
                if type(child) == "number" and menus[child] and child ~= menuIndex then
                    unpacked = { kind = "ring", ring = child }
                elseif builtIn then
                    -- This character's own built-in menu: linked as is (stored id, not an index).
                    unpacked = { kind = "ring", ring = builtIn.id, builtin = true }
                else
                    reason = type(slice.builtin) == "string" and Skip.BuiltIn or Skip.Invalid
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

        if menu.quickAction == "custom" then
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
    -- Nothing left in a menu (all its actions skipped): it isn't created.
    plan.menus = DropEmptyMenus(plan.menus)
    if #plan.menus == 0 then return nil, Ring_Data.ShareError.Nothing end

    local takenNames = {}
    for _, ring in ipairs(Ring_Data.GetRings()) do takenNames[ring.name] = true end
    for _, entry in ipairs(plan.menus) do
        entry.name = Utils_General.GetUniqueName(entry.sourceName, function(candidate) return takenNames[candidate] end, MAX_MENU_NAME)
        takenNames[entry.name] = true
    end

    -- Submenus: shown under the menu that contains them (the first one found).
    for index, entry in ipairs(plan.menus) do
        for _, slice in ipairs(entry.slices) do
            if slice.kind == "ring" and not slice.builtin and not plan.menus[slice.ring].parent then
                plan.menus[slice.ring].parent = index
            end
        end
    end
    return plan
end



-- Import: carrying it out

Ring_Data.ShareError = {
    Combat  = "combat",  -- macros (and menus) aren't created in combat
    Nothing = "nothing", -- reading: every menu in the string ends up empty
}

--- Creates the plan's macros and menus (new ones, nothing is replaced) in `scope`.
--- @return boolean ok
--- @return string|table reasonOrRings Ring_Data.ShareError, or the menus created (plan order)
function Ring_Data.ApplyShare(plan, scope)
    if InCombatLockdown() then return false, Ring_Data.ShareError.Combat end

    for _, macro in ipairs(plan.macros) do
        CreateMacro(macro.name, macro.icon, macro.body, false) -- account macro
    end

    -- Every menu first, so submenu slices can point at their new ids.
    local rings = {}
    for index, entry in ipairs(plan.menus) do
        rings[index] = Ring_Data.CreateRing(entry.name, scope)
    end
    for index, entry in ipairs(plan.menus) do
        local ring = rings[index]
        ring.slices = {}
        for _, slice in ipairs(entry.slices) do
            local stored = CopyTable(slice)
            if stored.kind == "ring" then
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
