---@meta
--[[
    Type definitions for the Lua language server (LuaLS). They describe the shapes of the addon's
    main tables, for hover docs and type checks in the editor. The game never loads this file (the
    .toc doesn't list it), so it holds no code.

    The menus' saved data is described in Code\Menu\Data\Store.lua, and each action kind's own
    fields in the header of its Code\Menu\Kinds\<Kind>.lua.
]]



-- Saved menus (Menu_Data)

--- A menu as saved. Its scope (account, class or character) is where it's stored, not a field.
---@class Menu
---@field id string unique across scopes, counted by Menu_Data ("1", "2", ...)
---@field name string
---@field actions Action[] its actions, in wheel order
---@field quickAction Action? the quick action in the center, fired by a tap (nil when it's empty)
---@field library string? a library menu's key (LibraryDefinition.key)
---@field order string[]? a library menu's remembered action order, as action keys
---@field removed RemovedAction[]? actions removed from a library menu, left out of its refills

--- An action. Its `kind` picks its definition (KindDefinition), which owns the other fields.
--- An action has no id of its own. Its identity is its key (Menu_Data.GetActionKey), like "spell:12345".
---@class Action
---@field kind string an action kind ("spell", "item", "submenu", ...)
---@field id (number|string)? the game's id of what it fires, such as a spell or item id (not unique to the action)
---@field name string? a name to show while the game can't give one (not cached yet, or elsewhere)
---@field menu string? for submenus (kind "submenu"), the submenu's Menu id
---@field spread boolean? for submenus, spread into the parent menu instead of scrolled
---@field icon (number|string)? an icon instead of its kind's (Menu_Actions)
---@field label string? a name instead of its kind's (Menu_Actions)

--- An action removed from a library menu, with what's needed to show it until it's restored.
---@class RemovedAction
---@field key string its identity (Menu_Data.GetActionKey)
---@field label string
---@field icon number|string



-- Menus as the player sees them (Menu_Live)

--- A menu right now, with hidden actions left out and spread submenus spread in.
---@class LiveMenu
---@field id string
---@field name string
---@field entries LiveEntry[]
---@field actions Action[] the entries' actions, in the same order
---@field quickAction Action? the quick action, while it can fire

--- One action in a LiveMenu.
---@class LiveEntry
---@field action Action what fires
---@field key string its identity (Menu_Data.GetActionKey), for Last Used
---@field ownerId string the menu that stores it, where its scroll position is kept
---@field ownerIndex integer its index in that menu



-- Registries

--- An action kind (Menu_Kinds.Register). Every field but `kind` is optional, and the header of
--- Code\Menu\Menu_Kinds.lua explains each one.
---@class KindDefinition
---@field kind string saved in every action, so one lowercase word that's never renamed
---@field versions string[]? the env.GameVersion values it exists in (nil for every version)
---@field validate (fun(action: Action, parentId: string): boolean, string?)?
---@field apply fun(button: Button, suffix: string, action: Action)? sets secure attributes (out of combat)
---@field icon (fun(action: Action, depth: integer?): number|string)?
---@field label (fun(action: Action): string)?
---@field cooldown (fun(action: Action): string?, (number|string)?)? a Menu_Kinds.Source value, and its id
---@field state (fun(action: Action): string?, (number|string)?)? like cooldown, for the icon's states in game
---@field condition (string|fun(action: Action): string)? the locale key of its visibility rule
---@field available (fun(action: Action, depth: integer?): boolean)? checked while `condition` is set
---@field tooltip (fun(tooltip: GameTooltip, action: Action): boolean)?
---@field search KindSearch?
---@field lookupId (fun(id: number): Action?, string?)? for a number typed in Add Action's search box
---@field cursor table<string, fun(info1: any, info2: any, info3: any): Action?>? drag and drop, by cursor type
---@field attributesChangeWith (fun(): any)? menus rebuild when this value changes
---@field noIconBorder boolean?
---@field underlay (fun(action: Action): string, table)? a texture and { r, g, b } drawn behind the icon
---@field share KindShare?

--- One result row in Add Action (Menu_Search).
---@class SearchCandidate
---@field kind string the kind column's label (the kind's search.label, or the kind)
---@field name string
---@field lname string the name in lower case, for matching
---@field icon number|string
---@field action Action the action it adds
---@field group integer? sorts later within a match rank (gear slots without a use)
---@field order integer? sorts within the same name (a spell's ranks)
---@field note string? shown under the name
---@field kindLabel string? replaces the kind column's text
---@field blocked string? why it can't be added (shown, but refused)

--- What a kind's search `scan` calls for each action it offers. The name and icon default to the
--- action's label and icon. It returns the candidate (SearchCandidate, Menu_Search.lua), for the
--- scan to add a note or ordering to.
---@alias SearchAdd fun(action: Action, name: string?, icon: (number|string)?): SearchCandidate?

--- How a kind is listed in the Add Action panel.
---@class KindSearch
---@field filter string? the filter entry that lists it (Menu_Search.Kinds)
---@field label string? the end of its kind column's locale key (the kind by default)
---@field events string[]? game events that make the cached list out of date
---@field scan fun(add: SearchAdd, menuId: string?) menuId is the menu being edited (for `dynamic` kinds)
---@field dynamic boolean? never cached

--- How a kind travels in a share string (Code\Menu\Data\Share.lua).
---@class KindShare
---@field pack (fun(action: Action, macros: table): Action?, string?)? what travels, or nil and why it's left out
---@field unpack (fun(action: Action, plan: table): Action?, string?)? back into a menu, or nil and why it's skipped

--- A library menu (Menu_Data.RegisterLibraryMenu). The header of Code\Menu\Data\Library.lua explains
--- each field.
---@class LibraryDefinition
---@field key string saved as Menu.library, so one lowercase word that's never renamed
---@field name string the locale key of its name
---@field events string[]? game events after which it refills (Menu_Auto)
---@field scan fun(): Action[] what it holds right now
---@field category string? a Menu_Data.LibraryCategory value (Situational by default)
---@field versions string[]? the env.GameVersion values it exists in (nil for every version)
