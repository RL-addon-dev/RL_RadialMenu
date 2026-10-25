--[[
    Menus_Tab (see Tab.lua): the sidebar's menu list. Its two tabs, the cards of each group, what
    the search box finds a menu by, and which groups stay closed between sessions.
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")
local Menus_Keybind = env.AX_Modules:Import("@\\Setting\\Menus\\Keybind")
local Menus_Common = env.AX_Modules:Import("@\\Setting\\Menus\\Common")
local Private = env.AX_Modules:Import("@\\Setting\\Menus\\Tab\\Private")

local PageMixin = Private.PageMixin

-- The sidebar list's tabs.
Private.NavTab = Utils_Standard.Strict({
    Mine    = "mine",    -- My Menus
    Library = "library", -- every library menu
}, "menu list tab")

-- The groups' ids. They're saved data (the keys of MenuListCollapsed, which groups are closed),
-- so they never change.
local GROUP_SCOPE      = "scope:"            -- .. a Menu_Data.Scope value
local GROUP_CATEGORY   = "category:"         -- .. a Menu_Data.LibraryCategory value
local GROUP_IN_USE     = "library:inuse"     -- the Library menus in use
local GROUP_CLASSES    = "other:classes"     -- other classes' menus
local GROUP_CHARACTERS = "other:characters"  -- other characters' menus



-- Cards

--- A card's detail line: its keybind, and its scope (Library for library menus).
---@param menu Menu
---@return string keyText
---@return string scopeText
local function FormatMenuMeta(menu)
    local _, scope = Menu_Data.GetMenu(menu.id)
    local key = Menu_Data.GetBinding(menu.id)
    local keyText = key and Menus_Keybind.GetDisplayText(key) or L["Config - Menus - Card - NoKey"]
    -- "Config - Menus - Card - Account", "- Class" or "- Character".
    local scopeText = Menu_Data.IsLibraryMenu(menu) and L["Config - Menus - Card - Library"]
        or L["Config - Menus - Card - " .. Menus_Common.GetScopeKeyName(scope)]
    return keyText, scopeText
end

--- What the list's search box finds a menu by, besides its name: its keybind (as its card shows
--- it), then its action names (its wedges and its center), so a key or a spell finds every menu
--- it's on. It's asked only while searching.
---@param menu Menu
---@param key string? its keybind ("CTRL-1"), nil when unbound
---@return fun(): string[]
local function SearchKeywords(menu, key)
    return function()
        local names = { key and Menus_Keybind.GetDisplayText(key) or nil }
        for _, action in ipairs(type(menu.actions) == "table" and menu.actions or {}) do
            names[#names + 1] = Menu_Actions.GetLabel(action)
        end
        local quick = Menu_Data.GetQuickAction(menu)
        if quick then names[#names + 1] = Menu_Actions.GetLabel(quick) end
        return names
    end
end

--- Adds a group row and its menus' cards (nothing for an empty group).
---@param items table[]
---@param id string
---@param title string
---@param menus Menu[]
---@param collapsed boolean? closed at first
local function AddGroup(items, id, title, menus, collapsed)
    if #menus == 0 then return end
    items[#items + 1] = { group = true, id = id, title = title, right = tostring(#menus), collapsed = collapsed }
    for _, menu in ipairs(menus) do
        local keyText, scopeText = FormatMenuMeta(menu)
        items[#items + 1] = { id = menu.id, title = menu.name, left = keyText, right = scopeText,
                              keywords = SearchKeywords(menu, Menu_Data.GetBinding(menu.id)) }
    end
end

--- A read-only group (menus that live elsewhere, dimmed, and opening one shows it locked), closed
--- at first.
---@param items table[]
---@param id string
---@param title string
---@param entries table[] { menu, key, owner = the card's right text }
local function AddElsewhereGroup(items, id, title, entries)
    if #entries == 0 then return end
    items[#items + 1] = {
        group = true, id = id, title = title, right = tostring(#entries), collapsed = true, muted = true,
    }
    for _, entry in ipairs(entries) do
        items[#items + 1] = {
            id = entry.menu.id, title = entry.menu.name, muted = true, right = entry.owner,
            left = entry.key and Menus_Keybind.GetDisplayText(entry.key) or L["Config - Menus - Card - NoKey"],
            keywords = SearchKeywords(entry.menu, entry.key),
        }
    end
end

--- Other classes' class menus, then other characters' menus (as of their last session).
---@param items table[]
local function AddElsewhere(items)
    local classes = {}
    for _, other in ipairs(Menu_Data.GetOtherClassMenus()) do
        local _, _, key = Menu_Data.GetOtherClassMenu(other.menu.id)
        classes[#classes + 1] = { menu = other.menu, key = key, owner = Menus_Common.GetClassName(other.class) }
    end
    AddElsewhereGroup(items, GROUP_CLASSES, L["Config - Menus - Nav - OtherClasses"], classes)

    local characters = {}
    for _, other in ipairs(Menu_Data.GetOtherCharacterMenus()) do
        characters[#characters + 1] = { menu = other.menu, key = other.key, owner = other.character.name }
    end
    AddElsewhereGroup(items, GROUP_CHARACTERS, L["Config - Menus - Nav - OtherCharacters"], characters)
end



-- The two tabs

--- My Menus: the user's menus by scope, then the Library menus in use (one group, bound first,
--- then those used as submenus of bound menus, see Menu_Data.GetOpenableMenus), then other
--- classes' and characters' menus (read-only).
---@return table[]
function PageMixin:GetMyMenusItems()
    local byScope, bound, inSubmenus = {}, {}, {}
    for _, scope in ipairs(Menu_Data.ScopeOrder) do byScope[scope] = {} end
    local _, openable = Menu_Data.GetOpenableMenus()
    for _, menu in ipairs(Menu_Data.GetMenus()) do
        if not Menu_Data.IsLibraryMenu(menu) then
            local _, scope = Menu_Data.GetMenu(menu.id)
            table.insert(byScope[scope], menu)
        elseif Menu_Data.GetBinding(menu.id) then
            table.insert(bound, menu)
        elseif openable[menu.id] then
            table.insert(inSubmenus, menu)
        end
    end
    local items = {}
    for _, scope in ipairs(Menu_Data.ScopeOrder) do
        AddGroup(items, GROUP_SCOPE .. scope, Menu_Data.GetScopeName(scope), byScope[scope])
    end
    for _, menu in ipairs(inSubmenus) do table.insert(bound, menu) end
    AddGroup(items, GROUP_IN_USE, L["Config - Menus - Nav - Library"], bound)
    AddElsewhere(items)
    return items
end

--- Library: every library menu by category, each group closed until opened.
---@return table[]
function PageMixin:GetLibraryItems()
    local byCategory = {}
    for _, category in ipairs(Menu_Data.LibraryCategoryOrder) do byCategory[category] = {} end
    for _, menu in ipairs(Menu_Data.GetMenus()) do
        if Menu_Data.IsLibraryMenu(menu) then
            table.insert(byCategory[Menu_Data.GetLibraryCategory(menu)], menu)
        end
    end
    local items = {}
    for _, category in ipairs(Menu_Data.LibraryCategoryOrder) do
        -- "Config - Menus - Library - <category>", one per Menu_Data.LibraryCategory value.
        local title = L["Config - Menus - Library - " .. category]
        AddGroup(items, GROUP_CATEGORY .. category, title, byCategory[category], true)
    end
    return items
end

--- The first menu card's id in `items`, or nil.
---@param items table[]
---@return string?
local function FirstMenuId(items)
    for _, item in ipairs(items) do
        if not item.group then return item.id end
    end
end

--- Refreshes the list, keeping a menu selected: the first of My Menus, else the first in the
--- Library.
function PageMixin:RefreshNav()
    if not self:GetSelectedMenu() then
        self.selectedMenuId = FirstMenuId(self:GetMyMenusItems()) or FirstMenuId(self:GetLibraryItems())
    end
    self.Nav:Refresh()
end

--- Shows one of the user's menus in the sidebar: the My Menus tab, its scope's group opened, and
--- the list scrolled to it.
---@param menuId string
---@param select boolean? also select it (one refresh for both)
function PageMixin:RevealInMyMenus(menuId, select)
    local _, scope = Menu_Data.GetMenu(menuId)
    if not scope then return end
    self.navTab = Private.NavTab.Mine
    self.Nav:SetGroupCollapsed(GROUP_SCOPE .. scope, false, true)
    if select then
        self.Nav:Select(menuId) -- refreshes and scrolls to it
    else
        self.Nav:Refresh()
        self.Nav:ScrollTo(menuId)
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
