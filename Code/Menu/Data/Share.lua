--[[
    Menu data: sharing menus as text (Import and Share in the Menus tab). It's used like this:

        local text, summary = Menu_Data.BuildShare({ menuId, ... })   -- the ticked menus
        local plan, reason, header = Menu_Data.ReadShare(text)          -- nothing changes yet
        local ok, reason = Menu_Data.ApplyShare(plan, Menu_Data.Scope.Account)

    A share holds the ticked menus and every submenu they contain. A library submenu travels as
    its key only, because it fills itself, and on import it links to the importer's own library
    menu. Keybinds, scope and a submenu's spread or scroll setting aren't shared. The string is
    made by ax_modules\\share-string, with the header { addon = "RLRM", version, game }, and only
    strings of this game import.

    The payload (FORMAT_VERSION 2) has two parts.
        menus   an array of { name, actions, quickAction }. A submenu action is
                { kind = "submenu", menu = <index in menus> }, or { kind = "submenu", library = <key> }
                for a library one.
        macros  [name] = { icon, body }, for the macro actions

    Version 1 strings still import (UpgradeVersion1). Their menus are { name, slices, quickAction =
    "custom", quickSlice }, and a submenu action is { kind = "ring", ring = <index> } or
    { kind = "ring", builtin = <key> }. Their oldest quickAction (an index into slices, or "last")
    is ignored, so the menu imports without one.

    Each action kind decides how it travels (Menu_Kinds `share`). By default it travels as it is,
    checked by its `validate` on import. Macros carry their text and are created on import (as
    account macros). Battle pets don't travel, because a pet belongs to its account, except a
    random favorite.

    ReadShare builds a plan with the menus' final names ("Name (2)" on a clash), the macros it will
    create, and what it skipped and why (Menu_Data.ShareSkip). The Import page shows it, and
    ApplyShare carries it out. Nothing from the string is ever run, but a new macro can be, so the
    page shows its text before importing.
]]

local env = select(2, ...)
local L = env.L
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")
local ShareString = env.AX_Modules:Import("ax_modules\\share-string")
local Utils_General = env.AX_Modules:Import("ax_modules\\utils\\general")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")

local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring

local ADDON = "RLRM"
local FORMAT_VERSION = 2
local MAX_MENUS = 50
local MAX_ACTIONS = 64         -- per menu
local MAX_MENU_NAME = 64       -- bytes
local MAX_MACRO_NAME = 16      -- the game's limit
local MAX_MACRO_BODY = 255     -- the game's limit
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120

-- Why an action was left out, counted per reason in a share summary or an import plan.
Menu_Data.ShareSkip = Utils_Standard.Strict({
    BattlePet    = "battlepet",     -- a pet belongs to the account that has it
    Library      = "library",       -- when importing, a library submenu this game doesn't have
    MissingMacro = "missing-macro", -- when sharing, the macro no longer exists
    MacroSlots   = "macro-slots",   -- when importing, no free account macro slots
    Invalid      = "invalid",       -- not an action of this game, or it failed its checks
    Empty        = "empty",         -- when sharing, a submenu with nothing left in it
}, "share skip reason")

-- Why a whole import was refused (besides ShareString.Error, for a string it can't read).
Menu_Data.ShareError = Utils_Standard.Strict({
    Combat  = "combat",  -- macros (and menus) aren't created in combat
    Nothing = "nothing", -- every menu in the string ends up empty
}, "share error")

-- BreakLoops' marks while it walks the submenus.
local VISITING, VISITED = 1, 2

--- Counts one more action left out for `reason`.
---@param skipped table<string, integer> counts by Menu_Data.ShareSkip reason
---@param reason string? Invalid when nil
local function CountSkip(skipped, reason)
    reason = reason or Menu_Data.ShareSkip.Invalid
    skipped[reason] = (skipped[reason] or 0) + 1
end

--- Drops the menus with nothing in them (no actions and no quick action) and the submenu links
--- to them. That can empty more menus, so it repeats, then renumbers the links. It works on shared
--- menus and on a plan's, which both link a submenu as { kind = "submenu", menu = <index> }.
---@param menus table[]
---@return table[] kept the menus left, in order
---@return table<integer, boolean> dropped the old indexes of the dropped menus
local function DropEmptyMenus(menus)
    local dropped = {}
    repeat
        local changed = false
        for index, menu in ipairs(menus) do
            if not dropped[index] and #menu.actions == 0 and not menu.quickAction then
                dropped[index], changed = true, true
            end
        end
        for index, menu in ipairs(menus) do
            if changed and not dropped[index] then
                for i = #menu.actions, 1, -1 do
                    local action = menu.actions[i]
                    if action.kind == Menu_Kinds.Kind.Submenu and not action.library and dropped[action.menu] then
                        table.remove(menu.actions, i)
                        if menu.skipped then CountSkip(menu.skipped, Menu_Data.ShareSkip.Empty) end -- an import's menu
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
        for _, action in ipairs(menu.actions) do
            if action.kind == Menu_Kinds.Kind.Submenu and not action.library then action.menu = newIndex[action.menu] end
        end
    end
    return kept, dropped
end

-- Share

--- What travels for `action`, from its kind's `share.pack` or else a copy. Nil and a reason when
--- it's left out.
---@param action Action
---@param macros table the share's macros, which `share.pack` adds to
---@return Action? packed
---@return string? reason a Menu_Data.ShareSkip value
local function PackAction(action, macros)
    local definition = Menu_Kinds.Get(action.kind)
    if not definition then return nil, Menu_Data.ShareSkip.Invalid end
    if definition.share and definition.share.pack then return definition.share.pack(action, macros) end
    return CopyTable(action)
end

--- Builds a share string from the ticked menus, adding their submenus.
---@param menuIds (string|number)[] the ticked menus' ids
---@return string text "" when nothing's left to share (every menu is empty)
---@return table summary { submenus, macros, skippedNames }. `submenus` lists the shared
---     submenus' names, `macros` the macros whose text travels too, and `skippedNames` what was
---     left out ({ [Menu_Data.ShareSkip] = { label, ... } }).
function Menu_Data.BuildShare(menuIds)
    -- The ticked menus, then every submenu they reach (depth first), each once. Any of them can
    -- live elsewhere (another class's or character's, Elsewhere.lua). Those are shared from their
    -- saved copy, so a menu travels whole wherever its submenus live.
    local menus, indexOf = {}, {}
    local function Add(id)
        local menu = Menu_Data.GetMenu(id) or (Menu_Data.GetElsewhereMenu(id))
        if not menu or Menu_Data.IsLibraryMenu(menu) or indexOf[menu.id] then return end
        menus[#menus + 1] = menu
        indexOf[menu.id] = #menus
        for _, action in ipairs(menu.actions) do
            if action.kind == Menu_Kinds.Kind.Submenu then Add(action.menu) end
        end
    end
    for _, id in ipairs(menuIds) do Add(id) end

    local packedMenus, macros, skippedNames = {}, {}, {}
    -- What's left out, by reason, each name once. The Share box lists it.
    local function AddSkip(reason, label)
        reason = reason or Menu_Data.ShareSkip.Invalid
        local names = skippedNames[reason] or {}
        skippedNames[reason] = names
        if not tContains(names, label) then names[#names + 1] = label end
    end
    for menuIndex, menu in ipairs(menus) do
        local packedMenu, newIndex = { name = menu.name, actions = {} }, {}
        for index, action in ipairs(menu.actions) do
            local packed, reason
            -- A submenu found nowhere is left out, and not listed as skipped. That's one with no
            -- saved copy, from a character that hasn't logged in since.
            local child = action.kind == Menu_Kinds.Kind.Submenu and indexOf[tostring(action.menu)]
            local elsewhere = not child and Menu_Data.IsElsewhere(action)
            if elsewhere then
                packed = nil
            elseif action.kind == Menu_Kinds.Kind.Submenu then
                local childMenu = not child and Menu_Data.GetMenu(action.menu)
                if child then
                    packed = { kind = Menu_Kinds.Kind.Submenu, menu = child }
                elseif childMenu and Menu_Data.IsLibraryMenu(childMenu) then
                    packed = { kind = Menu_Kinds.Kind.Submenu, library = childMenu.library }
                else
                    reason = Menu_Data.ShareSkip.Invalid
                end
            else
                packed, reason = PackAction(action, macros)
            end
            if packed then
                packed.spread = nil
                packedMenu.actions[#packedMenu.actions + 1] = packed
                newIndex[index] = #packedMenu.actions
            elseif not elsewhere then
                AddSkip(reason, Menu_Actions.GetLabel(action))
            end
        end

        local center = Menu_Data.GetQuickAction(menu)
        if center then
            local packed, reason = PackAction(center, macros)
            if packed then
                packedMenu.quickAction = packed
            else
                AddSkip(reason, Menu_Actions.GetLabel(center))
            end
        end
        packedMenus[menuIndex] = packedMenu
    end

    -- Menus with nothing left in them aren't shared, and neither are the links to them. A dropped
    -- submenu is listed as Empty. An empty menu that was ticked leaves nothing to share.
    local roots = {}
    for _, id in ipairs(menuIds) do
        if indexOf[tostring(id)] then roots[indexOf[tostring(id)]] = true end
    end
    local kept, dropped = DropEmptyMenus(packedMenus)
    local submenus = {}
    for index, menu in ipairs(menus) do
        if dropped[index] then
            if not roots[index] then AddSkip(Menu_Data.ShareSkip.Empty, menu.name) end
        elseif not roots[index] then
            submenus[#submenus + 1] = menu.name
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
---@return string? reason a Menu_Data.ShareSkip value
function PlanMixin:ResolveMacro(name)
    if self.macroNames[name] then return self.macroNames[name] end
    local data = type(name) == "string" and self.macroData[name]
    if type(data) ~= "table" or type(data.body) ~= "string" or #data.body > MAX_MACRO_BODY then
        return nil, Menu_Data.ShareSkip.Invalid
    end

    local existing = GetMacroIndexByName(name)
    if existing and existing > 0 and select(3, GetMacroInfo(existing)) == data.body then
        self.macroNames[name] = name
        return name
    end

    local accountMacros = GetNumMacros()
    if accountMacros + #self.macros >= MAX_ACCOUNT_MACROS then return nil, Menu_Data.ShareSkip.MacroSlots end

    local newName = Utils_General.GetUniqueName(name, function(candidate)
        local index = GetMacroIndexByName(candidate)
        return (index and index > 0) or self.reservedMacros[candidate] ~= nil
    end, MAX_MACRO_NAME)
    self.reservedMacros[newName] = true
    self.macros[#self.macros + 1] = {
        name = newName, sourceName = name, body = data.body,
        icon = ((type(data.icon) == "number" or type(data.icon) == "string") and data.icon) or Menu_Kinds.QUESTION_MARK_ICON,
    }
    self.macroNames[name] = newName
    return newName
end

--- An action from the string as it will be saved, through its kind's `share.unpack` and then its
--- `validate`. ReadShare handles submenus. Nil and a reason when it's skipped.
---@param action any
---@return Action? action
---@return string? reason a Menu_Data.ShareSkip value
function PlanMixin:UnpackAction(action)
    if type(action) ~= "table" or type(action.kind) ~= "string" or action.kind == Menu_Kinds.Kind.Submenu then
        return nil, Menu_Data.ShareSkip.Invalid
    end
    local definition = Menu_Kinds.Get(action.kind)
    if not definition then return nil, Menu_Data.ShareSkip.Invalid end -- another game's kind
    local unpacked, reason = CopyTable(action), nil
    if definition.share and definition.share.unpack then
        unpacked, reason = definition.share.unpack(unpacked, self)
        if not unpacked then return nil, reason end
    end
    if not Menu_Data.ValidateAction(nil, unpacked) then return nil, Menu_Data.ShareSkip.Invalid end
    return unpacked
end

--- Drops submenu actions that would make menus contain each other in a loop.
---@param entries table[] the plan's menus
local function BreakLoops(entries)
    local state = {} -- [index] = VISITING or VISITED
    local function Visit(index)
        state[index] = VISITING
        local entry = entries[index]
        for i = #entry.actions, 1, -1 do
            local action = entry.actions[i]
            if action.kind == Menu_Kinds.Kind.Submenu and not action.library then -- library menus hold no submenus
                if state[action.menu] == VISITING then
                    table.remove(entry.actions, i)
                    CountSkip(entry.skipped, Menu_Data.ShareSkip.Invalid)
                elseif not state[action.menu] then
                    Visit(action.menu)
                end
            end
        end
        state[index] = VISITED
    end
    for index in ipairs(entries) do
        if not state[index] then Visit(index) end
    end
end

--- A version 1 action in today's shape. Only a submenu changed. Its kind was "ring", and its
--- index or library key was in `ring` or `builtin`.
---@param action any
local function UpgradeVersion1Action(action)
    if type(action) ~= "table" or action.kind ~= "ring" then return end
    action.kind, action.menu, action.library = Menu_Kinds.Kind.Submenu, action.ring, action.builtin
    action.ring, action.builtin = nil, nil
end

--- Brings a version 1 payload's menus up to today's shape (see the header), in place.
---@param payload table
local function UpgradeVersion1(payload)
    for _, menu in ipairs(type(payload.menus) == "table" and payload.menus or {}) do
        if type(menu) == "table" then
            menu.actions, menu.slices = menu.slices, nil
            menu.quickAction = (menu.quickAction == "custom" and menu.quickSlice) or nil
            menu.quickSlice = nil
            for _, action in ipairs(type(menu.actions) == "table" and menu.actions or {}) do
                UpgradeVersion1Action(action)
            end
            UpgradeVersion1Action(menu.quickAction)
        end
    end
end

--- Reads a share string into an import plan. Nothing changes until ApplyShare.
---
--- The plan has `menus`, each { name, sourceName, actions, quickAction?, parent?, skipped },
--- where `skipped` counts what was left out by Menu_Data.ShareSkip reason. It also has `macros`
--- to create, each { name, sourceName, body, icon }.
---@param text string
---@return table? plan
---@return string? reason a ShareString.Error, or Menu_Data.ShareError.Nothing, when refused
---@return table? header when refused after the header could be read (header.game is the other game)
function Menu_Data.ReadShare(text)
    local payload, headerOrError, refusedHeader = ShareString.Decode(text, {
        addon = ADDON, maxVersion = FORMAT_VERSION, game = env.GAME_VERSION,
    })
    if not payload then return nil, headerOrError, refusedHeader end
    if type(payload) == "table" and headerOrError.version < 2 then UpgradeVersion1(payload) end
    local menus = type(payload) == "table" and payload.menus
    if type(menus) ~= "table" or #menus == 0 or #menus > MAX_MENUS then return nil, ShareString.Error.Invalid end

    local plan = CreateFromMixins(PlanMixin)
    plan.menus, plan.macros = {}, {}
    plan.macroData = type(payload.macros) == "table" and payload.macros or {}
    plan.macroNames, plan.reservedMacros = {}, {}

    for menuIndex, menu in ipairs(menus) do
        if type(menu) ~= "table" or type(menu.actions) ~= "table" or #menu.actions > MAX_ACTIONS then
            return nil, ShareString.Error.Invalid
        end
        local sourceName = type(menu.name) == "string" and strtrim(menu.name) or ""
        if sourceName == "" then sourceName = L["Config - Menus - NewMenu - DefaultName"] end

        local entry = { sourceName = sourceName, actions = {}, skipped = {} }
        for _, action in ipairs(menu.actions) do
            local unpacked, reason
            if type(action) == "table" and action.kind == Menu_Kinds.Kind.Submenu then
                local child = action.menu
                local library = type(action.library) == "string" and Menu_Data.GetLibraryMenu(action.library)
                if type(child) == "number" and menus[child] and child ~= menuIndex then
                    unpacked = { kind = Menu_Kinds.Kind.Submenu, menu = child }
                elseif library then
                    -- This character's own library menu, linked by its saved id (not an index).
                    unpacked = { kind = Menu_Kinds.Kind.Submenu, menu = library.id, library = true }
                else
                    reason = (type(action.library) == "string" and Menu_Data.ShareSkip.Library)
                        or Menu_Data.ShareSkip.Invalid
                end
            else
                unpacked, reason = plan:UnpackAction(action)
            end
            if unpacked then
                entry.actions[#entry.actions + 1] = unpacked
            else
                CountSkip(entry.skipped, reason)
            end
        end

        if menu.quickAction ~= nil then
            local quickAction, reason = plan:UnpackAction(menu.quickAction)
            if quickAction then
                entry.quickAction = quickAction
            else
                CountSkip(entry.skipped, reason)
            end
        end
        plan.menus[menuIndex] = entry
    end

    BreakLoops(plan.menus)
    -- A menu with nothing left in it (all its actions skipped) isn't created.
    plan.menus = DropEmptyMenus(plan.menus)
    if #plan.menus == 0 then return nil, Menu_Data.ShareError.Nothing end

    local takenNames = {}
    for _, menu in ipairs(Menu_Data.GetMenus()) do takenNames[menu.name] = true end
    for _, entry in ipairs(plan.menus) do
        entry.name = Utils_General.GetUniqueName(entry.sourceName, function(candidate) return takenNames[candidate] end, MAX_MENU_NAME)
        takenNames[entry.name] = true
    end

    -- Each submenu is shown under the first menu found that contains it.
    for index, entry in ipairs(plan.menus) do
        for _, action in ipairs(entry.actions) do
            if action.kind == Menu_Kinds.Kind.Submenu and not action.library and not plan.menus[action.menu].parent then
                plan.menus[action.menu].parent = index
            end
        end
    end
    return plan
end

-- Import: carrying it out

--- Creates the plan's macros and menus in `scope`. They're all new, nothing is replaced.
---@param plan table from Menu_Data.ReadShare
---@param scope string a Menu_Data.Scope value
---@return boolean ok
---@return string|Menu[] reasonOrMenus a Menu_Data.ShareError value, or the menus created in plan order
function Menu_Data.ApplyShare(plan, scope)
    if InCombatLockdown() then return false, Menu_Data.ShareError.Combat end

    for _, macro in ipairs(plan.macros) do
        CreateMacro(macro.name, macro.icon, macro.body, false) -- account macro
    end

    -- Every menu first, so submenu actions can point at their new ids.
    local menus = {}
    for index, entry in ipairs(plan.menus) do
        menus[index] = Menu_Data.CreateMenu(entry.name, scope)
    end
    for index, entry in ipairs(plan.menus) do
        local menu = menus[index]
        menu.actions = {}
        for _, action in ipairs(entry.actions) do
            local stored = CopyTable(action)
            if stored.kind == Menu_Kinds.Kind.Submenu then
                if stored.library then stored.library = nil else stored.menu = menus[stored.menu].id end
            end
            menu.actions[#menu.actions + 1] = stored
        end
        menu.quickAction = entry.quickAction and CopyTable(entry.quickAction) or nil
        Private.NormalizeMenu(menu)
    end
    Private.Changed()
    return true, menus
end
