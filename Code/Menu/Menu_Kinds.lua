--[[
    Action kinds: one definition per kind of action (Code\Menu\Kinds\<Kind>.lua, listed in
    Kinds\Kinds.xml), registered here. Everything kind-specific lives in its definition, and
    Menu_Actions, Menu_Search, Menu_Data and Menu_Auto loop over them. Adding a kind means adding a
    file, its name in Menu_Kinds.Kind, and its locale strings.

    Types.lua (KindDefinition) describes every field. A registration looks like this:

        Menu_Kinds.Register({
            kind      = Menu_Kinds.Kind.Item,
            validate  = function(action, parentId) return ok, err end,   -- saved and added actions
            apply     = function(button, suffix, action) end,           -- secure attributes (out of combat)
            icon      = function(action, depth) return icon end,
            label     = function(action) return text end,
            condition = "item",                                        -- the visibility rule's locale key
            available = function(action, depth) return boolean end,    -- checked while `condition` is set
            search    = { filter = "item", events = { "BAG_UPDATE_DELAYED" }, scan = function(add, menuId) end },
            cursor    = { item = function(info1, info2, info3) return action end }, -- drag and drop
        })

    Kind names are one lowercase word ("worldmarker", "equipslot"), not CamelCase like the code's
    own names. They're data, saved in every menu (action.kind, and action keys such as
    "targetmarker:8"), and they read like the game's own ids they sit next to (secure action types
    "worldmarker" and "raidtarget", cursor types "battlepet" and "petaction"). Library menu keys
    follow the same rule (Library.lua). Renaming one after release needs a migration
    (Data\Migrations\).

    A kind for other game versions isn't registered. It isn't offered in Add Action, drag and drop
    or id lookups, and saved actions of that kind are hidden in game (Menu_Actions). A library menu
    must only use kinds that exist in all of its versions.

    A definition can also be search-only (Kinds\Profession.lua), with just `search`, listing actions
    of another kind (spell actions) under its own filter. Nothing is ever saved with its kind.

    Every field except `kind` is optional. Definitions are asked in registration order (filter
    entries, cursor handlers, id lookups), so each handler checks its own case (item skips toys).

    Also here are the helpers kind definitions share: secure attribute setters, tooltips, and the
    addon's symbol icons. Game state that isn't about menus is in Code\Utils\.
]]

local addonName, env = ...
local L = env.L
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Kinds = env.AX_Modules:New("@\\Menu\\Kinds")

local order, byKind = {}, {}

-- Every kind's name, as saved in menus (action.kind). Never rename a value (see the header).
Menu_Kinds.Kind = Utils_Standard.Strict({
    Submenu        = "submenu",
    Spell          = "spell",
    Pet            = "pet",
    Item           = "item",
    Toy            = "toy",
    Mount          = "mount",
    BattlePet      = "battlepet",
    Macro          = "macro",
    Emote          = "emote",
    TargetMarker   = "targetmarker",
    WorldMarker    = "worldmarker",
    EquipSlot      = "equipslot",
    EquipItem      = "equipitem",
    EquipSet       = "equipset",
    Extra          = "extra",
    Zone           = "zone",
    House          = "house",
    ActionSlot     = "actionslot",
    Close          = "close",
    LastUsed       = "lastused",
    First          = "first",
    Spec           = "spec",
    Loadout        = "loadout",
    -- Search only, never saved (see the header).
    EquipMenus     = "equipmenus",
    ActionBarMenus = "actionbarmenus",
    Profession     = "profession",
}, "action kind")

-- What a kind's `cooldown` and `state` return first: what the icon's cooldown and state follow,
-- with the id (or spell name) after it. Menu_Layout's action icons read them.
Menu_Kinds.Source = Utils_Standard.Strict({
    Spell     = "spell",     -- a spell id or name
    Item      = "item",      -- an item id
    Inventory = "inventory", -- an equipped slot
}, "cooldown source")

-- The addon's own per-action secure attributes, set by kinds next to the game's ("*close-sN"...).
-- Menu_Secure's PRE_CLICK snippet reads them by these names, spelled out because snippets can't
-- see Lua constants, so a rename has to change both.
Menu_Kinds.ActionAttribute = Utils_Standard.Strict({
    Close       = "close",       -- picking it is a cancel (Kinds\Close.lua)
    LastUsed    = "lastused",    -- fires the menu's last used action (Kinds\LastUsed.lua)
    First       = "first",       -- fires the menu's first wedge (Kinds\First.lua)
    PagedButton = "pagedbutton", -- an Action Bar 1 button, which follows the bar's page (Kinds\ActionBar.lua)
}, "action attribute")

Menu_Kinds.QUESTION_MARK_ICON = 134400

-- Raid target icons by number (1 Star to 8 Skull), and the raid manager's reset button. Target and
-- world markers both show them.
Menu_Kinds.RAID_TARGET_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
Menu_Kinds.CLEAR_MARKERS_ICON = "atlas:GM-raidMarker-reset"



-- Registry

--- Registers an action kind (see the header). It isn't registered when it isn't for this game.
---@param definition KindDefinition
---@return KindDefinition? definition nil when it isn't for this game
function Menu_Kinds.Register(definition)
    assert(type(definition.kind) == "string", "action kind needs a name")
    if not env.IsForThisGame(definition.versions) then return nil end
    assert(not byKind[definition.kind], "action kind registered twice: " .. definition.kind)
    byKind[definition.kind] = definition
    order[#order + 1] = definition
    return definition
end

--- The definition of `kind`, or nil when it isn't registered in this game.
---@param kind string a Menu_Kinds.Kind value
---@return KindDefinition?
function Menu_Kinds.Get(kind)
    return byKind[kind]
end

--- Every definition, in registration order.
---@return KindDefinition[]
function Menu_Kinds.All()
    return order
end

--- A search `scan` that offers one action of `kind` with no fields of its own (Close, Extra, ...).
---@param kind string a Menu_Kinds.Kind value
---@return fun(add: fun(action: Action))
function Menu_Kinds.ScanOne(kind)
    return function(add) add({ kind = kind }) end
end



-- Symbols

-- Icons the addon ships for actions the game has none for (emotes). Each is
-- Art\Symbols\<name>.png, a white game-icons.net symbol on transparency (made by
-- Art\Symbols\make_symbols.py). They're drawn tinted (Menu_Layout.SetIcon), and kinds using them
-- leave out the action button border (noIconBorder).
local SYMBOL_PATH = "Interface\\AddOns\\" .. addonName .. "\\Art\\Symbols\\"
-- Each game's own UI metal, as the addon's settings art has it. Elsewhere that's its warm grey metal
-- (#9d988f, the checkbox and slider trim's lighter tone), and in WoW Forever the copper of its
-- Forever recolour (#966845, Art\recolor_forever.py's trim).
Menu_Kinds.SYMBOL_COLOR = (env.GAME_VERSION == env.GameVersion.Forever
    and { 0x96 / 255, 0x68 / 255, 0x45 / 255 }) -- copper
    or { 0x9d / 255, 0x98 / 255, 0x8f / 255 }   -- silver

--- The icon of symbol `name` (Art\Symbols\<name>.png).
---@param name string
---@return string
function Menu_Kinds.GetSymbol(name)
    return SYMBOL_PATH .. name .. ".png"
end

--- Whether `icon` is one of the addon's symbols, which are drawn tinted.
---@param icon any
---@return boolean
function Menu_Kinds.IsSymbol(icon)
    return type(icon) == "string" and icon:sub(1, #SYMBOL_PATH) == SYMBOL_PATH
end



-- Secure attributes

--- Sets secure attribute `name` for the action under `suffix`. Attributes use a "*" modifier
--- wildcard, so the action still fires while the menu's modifier keys (like CTRL-SHIFT) are held
--- on release.
---@param button Button
---@param name string
---@param suffix string
---@param value any
function Menu_Kinds.SetSlotAttribute(button, name, suffix, value)
    button:SetAttribute("*" .. name .. "-" .. suffix, value)
end

--- Sets a secure action type and the attribute of the same name, like type "item" with item
--- "item:6948", or type "macro" with macro "Name".
---@param button Button
---@param suffix string
---@param actionType string
---@param value any
function Menu_Kinds.SetAction(button, suffix, actionType, value)
    Menu_Kinds.SetSlotAttribute(button, "type", suffix, actionType)
    Menu_Kinds.SetSlotAttribute(button, actionType, suffix, value)
end

--- Runs `text` as a macro.
---@param button Button
---@param suffix string
---@param text string
function Menu_Kinds.SetMacroText(button, suffix, text)
    Menu_Kinds.SetSlotAttribute(button, "type", suffix, "macro")
    Menu_Kinds.SetSlotAttribute(button, "macro", suffix, nil)
    Menu_Kinds.SetSlotAttribute(button, "macrotext", suffix, text)
end

--- Casts `spell`, a name or an id.
---@param button Button
---@param suffix string
---@param spell string|number
function Menu_Kinds.SetSpell(button, suffix, spell)
    Menu_Kinds.SetAction(button, suffix, "spell", spell)
end

-- Hidden plain buttons for actions the game has no secure action type for (changing spec,
-- loading a talent build). The action "clicks" one, and its OnClick makes the call. There's one
-- per key, created on first use (frames can't be destroyed, and there are only a few).
local clickHandlers = {}

--- Makes the action run `onClick()`. That's insecure code, so only for calls that aren't
--- protected, and the game still refuses some of them in combat. Call it out of combat.
---@param button Button
---@param suffix string
---@param key string names the handler, like "spec:250"
---@param onClick fun()
function Menu_Kinds.SetClick(button, suffix, key, onClick)
    local handler = clickHandlers[key]
    if not handler then
        handler = CreateFrame("Button", nil, UIParent)
        handler:Hide()
        clickHandlers[key] = handler
    end
    handler:SetScript("OnClick", function() onClick() end)
    Menu_Kinds.SetSlotAttribute(button, "type", suffix, "click")
    Menu_Kinds.SetSlotAttribute(button, "clickbutton", suffix, handler)
end

--- Makes the action fire nothing, like a submenu, or a zone ability while there is none.
---@param button Button
---@param suffix string
function Menu_Kinds.ClearAction(button, suffix)
    Menu_Kinds.SetSlotAttribute(button, "type", suffix, nil)
end

--- For a SetClick action the game refuses in combat. In combat, it says so in chat and returns
--- true, so the caller stops.
---@return boolean refused
function Menu_Kinds.RefuseInCombat()
    if not InCombatLockdown() then return false end
    env.Print(ERR_NOT_IN_COMBAT or L["Config - Menus - Error - InCombat"])
    return true
end



-- Tooltips

--- Shows `title` in white, with `description` under it, wrapped (when there is one).
---@param tooltip GameTooltip
---@param title string
---@param description string?
---@return boolean handled always true, for a kind's `tooltip`
function Menu_Kinds.SetTooltipText(tooltip, title, description)
    tooltip:SetText(title, 1, 1, 1)
    if description then tooltip:AddLine(description, nil, nil, nil, true) end
    return true
end
