---@meta
--[[
    Type definitions for the Lua language server (LuaLS). They describe the shapes of the addon's
    main tables, for hover docs and type checks in the editor. The game never loads this file (the
    .toc doesn't list it), so it holds no code.

    The menus' saved data is described in Code\Ring\Data\Store.lua, and each action kind's own
    fields in the header of its Code\Ring\Kinds\<Kind>.lua.
]]



-- Saved menus (Ring_Data)

--- A menu as saved. Its scope (account, class or character) is where it's stored, not a field.
---@class Ring
---@field id string unique across scopes, counted by Ring_Data ("1", "2", ...)
---@field name string
---@field slices Slice[] its actions, in wheel order
---@field quickAction string a Ring_Data.QuickAction value, "none" or "custom" (then `quickSlice` fires on a tap)
---@field quickSlice Slice? the quick action in the center
---@field builtin string? a built-in menu's key (BuiltInDefinition.key)
---@field order string[]? a built-in menu's remembered action order, as slice keys
---@field removed RemovedAction[]? actions removed from a built-in menu, left out of its refills

--- An action. Its `kind` picks its definition (KindDefinition), which owns the other fields.
--- A slice has no id of its own. Its identity is its key (Ring_Data.GetSliceKey), like "spell:12345".
---@class Slice
---@field kind string an action kind ("spell", "item", "ring", ...)
---@field id (number|string)? the game's id of what it fires, such as a spell or item id (not unique to the slice)
---@field name string? a name to show while the game can't give one (not cached yet, or elsewhere)
---@field ring string? for submenus (kind "ring"), the submenu's Ring id
---@field expand boolean? for submenus, spread into the parent menu instead of scrolled

--- An action removed from a built-in menu, with what's needed to show it until it's restored.
---@class RemovedAction
---@field key string its identity (Ring_Data.GetSliceKey)
---@field label string
---@field icon number|string



-- Menus as the player sees them (Ring_Live)

--- A menu right now, with hidden actions left out and spread submenus spread in.
---@class LiveRing
---@field id string
---@field name string
---@field entries LiveEntry[]
---@field slices Slice[] the entries' slices, in the same order
---@field quickSlice Slice? the quick action, while it can fire

--- One action in a LiveRing.
---@class LiveEntry
---@field slice Slice what fires
---@field key string its identity (Ring_Data.GetSliceKey), for Last Used
---@field ownerId string the menu that stores it, where its scroll position is kept
---@field ownerIndex integer its index in that menu



-- Registries

--- An action kind (Ring_Kinds.Register). Every field but `kind` is optional, and the header of
--- Code\Ring\Ring_Kinds.lua explains each one.
---@class KindDefinition
---@field kind string saved in every slice, so one lowercase word that's never renamed
---@field versions string[]? the env.GameVersion values it exists in (nil for every version)
---@field validate (fun(slice: Slice, parentId: string): boolean, string?)?
---@field apply fun(button: Button, suffix: string, slice: Slice)? sets secure attributes (out of combat)
---@field icon (fun(slice: Slice, depth: integer?): number|string)?
---@field label (fun(slice: Slice): string)?
---@field cooldown (fun(slice: Slice): string, number)? "spell", "item" or "inventory", and its id
---@field state (fun(slice: Slice): string, number)? like cooldown, for the icon's states in game
---@field condition (string|fun(slice: Slice): string)? the locale key of its visibility rule
---@field available (fun(slice: Slice, depth: integer?): boolean)? checked while `condition` is set
---@field tooltip (fun(tooltip: GameTooltip, slice: Slice): boolean)?
---@field search KindSearch?
---@field lookupId (fun(id: number): Slice?, string?)? for a number typed in Add Action's search box
---@field cursor table<string, fun(info1: any, info2: any, info3: any): Slice?>? drag and drop, by cursor type
---@field attributesChangeWith (fun(): any)? menus rebuild when this value changes
---@field noIconBorder boolean?
---@field underlay (fun(slice: Slice): string, table)? a texture and { r, g, b } drawn behind the icon
---@field share KindShare?

--- How a kind is listed in the Add Action panel.
---@class KindSearch
---@field filter string? the filter entry that lists it (Ring_Search.Kinds)
---@field label string? the end of its kind column's locale key (the kind by default)
---@field events string[]? game events that make the cached list out of date
---@field scan fun(add: fun(slice: Slice, name: string?, icon: (number|string)?), ringId: string)
---@field dynamic boolean? never cached

--- How a kind travels in a share string (Code\Ring\Data\Share.lua).
---@class KindShare
---@field pack (fun(slice: Slice, macros: table): Slice?, string?)? what travels, or nil and why it's left out
---@field unpack (fun(slice: Slice, plan: table): Slice?, string?)? back into a menu, or nil and why it's skipped

--- A built-in menu (Ring_Data.RegisterBuiltIn). The header of Code\Ring\Data\BuiltIn.lua explains
--- each field.
---@class BuiltInDefinition
---@field key string saved as Ring.builtin, so one lowercase word that's never renamed
---@field name string the locale key of its name
---@field events string[]? game events after which it refills (Ring_Auto)
---@field scan fun(): Slice[] what it holds right now
---@field category string? a Ring_Data.LibraryCategory value (Situational by default)
---@field versions string[]? the env.GameVersion values it exists in (nil for every version)
