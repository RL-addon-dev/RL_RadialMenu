--[[
    Rings_Tab (see Tab.lua): the sidebar's menu list. Its two tabs, the cards of each group, what
    the search box finds a menu by, and which groups stay closed between sessions.
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Rings_Keybind = env.AX_Modules:Import("@\\Setting\\Rings\\Keybind")
local Rings_Common = env.AX_Modules:Import("@\\Setting\\Rings\\Common")
local Private = env.AX_Modules:Import("@\\Setting\\Rings\\Tab\\Private")

local PageMixin = Private.PageMixin

-- The sidebar list's tabs.
Private.NavTab = Utils_Standard.Strict({
    Mine    = "mine",    -- My Menus
    Library = "library", -- every built-in menu
}, "menu list tab")

-- The groups' ids. They're saved data (the keys of MenuListCollapsed, which groups are closed),
-- so they never change.
local GROUP_SCOPE      = "scope:"            -- .. a Ring_Data.Scope value
local GROUP_CATEGORY   = "category:"         -- .. a Ring_Data.LibraryCategory value
local GROUP_IN_USE     = "library:inuse"     -- the Library menus in use
local GROUP_CLASSES    = "other:classes"     -- other classes' menus
local GROUP_CHARACTERS = "other:characters"  -- other characters' menus



-- Cards

--- A card's detail line: its keybind, and its scope (Library for built-in menus).
---@param ring Ring
---@return string keyText
---@return string scopeText
local function FormatRingMeta(ring)
    local _, scope = Ring_Data.GetRing(ring.id)
    local key = Ring_Data.GetBinding(ring.id)
    local keyText = key and Rings_Keybind.GetDisplayText(key) or L["Config - Rings - Card - NoKey"]
    -- "Config - Rings - Card - Account", "- Class" or "- Character".
    local scopeText = Ring_Data.IsBuiltIn(ring) and L["Config - Rings - Card - Library"]
        or L["Config - Rings - Card - " .. Rings_Common.GetScopeKeyName(scope)]
    return keyText, scopeText
end

--- What the list's search box finds a menu by, besides its name: its keybind (as its card shows
--- it), then its action names (its wedges and its center), so a key or a spell finds every menu
--- it's on. It's asked only while searching.
---@param ring Ring
---@param key string? its keybind ("CTRL-1"), nil when unbound
---@return fun(): string[]
local function SearchKeywords(ring, key)
    return function()
        local names = { key and Rings_Keybind.GetDisplayText(key) or nil }
        for _, slice in ipairs(type(ring.slices) == "table" and ring.slices or {}) do
            names[#names + 1] = Ring_Actions.GetLabel(slice)
        end
        local quick = Ring_Data.GetQuickActionSlice(ring)
        if quick then names[#names + 1] = Ring_Actions.GetLabel(quick) end
        return names
    end
end

--- Adds a group row and its menus' cards (nothing for an empty group).
---@param items table[]
---@param id string
---@param title string
---@param rings Ring[]
---@param collapsed boolean? closed at first
local function AddGroup(items, id, title, rings, collapsed)
    if #rings == 0 then return end
    items[#items + 1] = { group = true, id = id, title = title, right = tostring(#rings), collapsed = collapsed }
    for _, ring in ipairs(rings) do
        local keyText, scopeText = FormatRingMeta(ring)
        items[#items + 1] = { id = ring.id, title = ring.name, left = keyText, right = scopeText,
                              keywords = SearchKeywords(ring, Ring_Data.GetBinding(ring.id)) }
    end
end

--- A read-only group (menus that live elsewhere, dimmed, and opening one shows it locked), closed
--- at first.
---@param items table[]
---@param id string
---@param title string
---@param entries table[] { ring, key, owner = the card's right text }
local function AddElsewhereGroup(items, id, title, entries)
    if #entries == 0 then return end
    items[#items + 1] = {
        group = true, id = id, title = title, right = tostring(#entries), collapsed = true, muted = true,
    }
    for _, entry in ipairs(entries) do
        items[#items + 1] = {
            id = entry.ring.id, title = entry.ring.name, muted = true, right = entry.owner,
            left = entry.key and Rings_Keybind.GetDisplayText(entry.key) or L["Config - Rings - Card - NoKey"],
            keywords = SearchKeywords(entry.ring, entry.key),
        }
    end
end

--- Other classes' class menus, then other characters' menus (as of their last session).
---@param items table[]
local function AddElsewhere(items)
    local classes = {}
    for _, other in ipairs(Ring_Data.GetOtherClassRings()) do
        local _, _, key = Ring_Data.GetOtherClassRing(other.ring.id)
        classes[#classes + 1] = { ring = other.ring, key = key, owner = Rings_Common.GetClassName(other.class) }
    end
    AddElsewhereGroup(items, GROUP_CLASSES, L["Config - Rings - Nav - OtherClasses"], classes)

    local characters = {}
    for _, other in ipairs(Ring_Data.GetOtherCharacterRings()) do
        characters[#characters + 1] = { ring = other.ring, key = other.key, owner = other.character.name }
    end
    AddElsewhereGroup(items, GROUP_CHARACTERS, L["Config - Rings - Nav - OtherCharacters"], characters)
end



-- The two tabs

--- My Menus: the user's menus by scope, then the Library menus in use (one group, bound first,
--- then those used as submenus of bound menus, see Ring_Data.GetOpenableRings), then other
--- classes' and characters' menus (read-only).
---@return table[]
function PageMixin:GetMyMenusItems()
    local byScope, bound, inSubmenus = {}, {}, {}
    for _, scope in ipairs(Ring_Data.ScopeOrder) do byScope[scope] = {} end
    local _, openable = Ring_Data.GetOpenableRings()
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if not Ring_Data.IsBuiltIn(ring) then
            local _, scope = Ring_Data.GetRing(ring.id)
            table.insert(byScope[scope], ring)
        elseif Ring_Data.GetBinding(ring.id) then
            table.insert(bound, ring)
        elseif openable[ring.id] then
            table.insert(inSubmenus, ring)
        end
    end
    local items = {}
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        AddGroup(items, GROUP_SCOPE .. scope, Ring_Data.GetScopeName(scope), byScope[scope])
    end
    for _, ring in ipairs(inSubmenus) do table.insert(bound, ring) end
    AddGroup(items, GROUP_IN_USE, L["Config - Rings - Nav - Library"], bound)
    AddElsewhere(items)
    return items
end

--- Library: every built-in menu by category, each group closed until opened.
---@return table[]
function PageMixin:GetLibraryItems()
    local byCategory = {}
    for _, category in ipairs(Ring_Data.LibraryCategoryOrder) do byCategory[category] = {} end
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if Ring_Data.IsBuiltIn(ring) then
            table.insert(byCategory[Ring_Data.GetLibraryCategory(ring)], ring)
        end
    end
    local items = {}
    for _, category in ipairs(Ring_Data.LibraryCategoryOrder) do
        -- "Config - Rings - Library - <category>", one per Ring_Data.LibraryCategory value.
        local title = L["Config - Rings - Library - " .. category]
        AddGroup(items, GROUP_CATEGORY .. category, title, byCategory[category], true)
    end
    return items
end

--- The first menu card's id in `items`, or nil.
---@param items table[]
---@return string?
local function FirstRingId(items)
    for _, item in ipairs(items) do
        if not item.group then return item.id end
    end
end

--- Refreshes the list, keeping a menu selected: the first of My Menus, else the first in the
--- Library.
function PageMixin:RefreshNav()
    if not self:GetSelectedRing() then
        self.selectedRingId = FirstRingId(self:GetMyMenusItems()) or FirstRingId(self:GetLibraryItems())
    end
    self.Nav:Refresh()
end

--- Shows one of the user's menus in the sidebar: the My Menus tab, its scope's group opened, and
--- the list scrolled to it.
---@param ringId string
---@param select boolean? also select it (one refresh for both)
function PageMixin:RevealInMyMenus(ringId, select)
    local _, scope = Ring_Data.GetRing(ringId)
    if not scope then return end
    self.navTab = Private.NavTab.Mine
    self.Nav:SetGroupCollapsed(GROUP_SCOPE .. scope, false, true)
    if select then
        self.Nav:Select(ringId) -- refreshes and scrolls to it
    else
        self.Nav:Refresh()
        self.Nav:ScrollTo(ringId)
    end
end

--- Which groups the user closed or opened ([groupId] = true or false), kept account-wide. It's
--- looked up on each use, because the settings can be built before the saved variables are loaded.
---@return table
function Private.SavedCollapsedGroups()
    local function Stored(create)
        local db = Config.DBGlobalPersistent:GetData()
        if not db then return nil end
        if create and type(db.MenuListCollapsed) ~= "table" then db.MenuListCollapsed = {} end
        return type(db.MenuListCollapsed) == "table" and db.MenuListCollapsed or nil
    end
    return setmetatable({}, {
        __index = function(_, groupId)
            local stored = Stored(false)
            return stored and stored[groupId]
        end,
        __newindex = function(_, groupId, collapsed)
            local stored = Stored(true)
            if stored then stored[groupId] = collapsed end
        end,
    })
end
