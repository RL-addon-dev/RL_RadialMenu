--[[
    Menu_Live: menus the way the player sees them. It's the one place that walks submenus, and the
    in-game menus (Menu_Secure), the settings preview, the wheel's badges and the submenu kind's
    visibility all ask here.

    The rules.
        - Actions with nothing to fire are left out (Menu_Actions.IsActionAvailable).
        - Spread submenus ({ spread = true }) are replaced by their own actions, at any depth.
        - Scroll submenus ({ kind = "submenu" }, not spread) stay one action. The mouse wheel cycles
          through their scroll list, which is the submenu's live actions with every submenu inside
          it spread in (whatever its own setting, at any depth). So a menu is at most two levels
          deep in game: the menu you pressed, and a scroll wedge's flat list. The wedge shows the
          current action.
        - A menu never contains itself. Loops are refused when editing, and walking skips them
          anyway.

    A live entry (LiveEntry) is { action, key, ownerId, ownerIndex }.
        action      what fires
        key         its identity (Menu_Data.GetActionKey), for Last Used
        ownerId     the menu that stores it, and its index there (where a scroll position is kept)
        ownerIndex
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Actions = env.AX_Modules:Import("@\\Menu\\Actions")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Live = env.AX_Modules:New("@\\Menu\\Live")

local MAX_DEPTH = 8 -- only a backstop, since loops are also caught by `visited`

--- Whether `action` is a submenu, spread or not.
---@param action Action?
---@return boolean
function Menu_Live.IsSubmenu(action)
    return action ~= nil and action.kind == Menu_Kinds.Kind.Submenu
end

--- Whether `action` is a submenu spread into its parent.
---@param action Action?
---@return boolean
function Menu_Live.IsSpread(action)
    return Menu_Live.IsSubmenu(action) and (action --[[@as Action]]).spread == true
end

---@param entries LiveEntry[]
---@param action Action
---@param ownerId string
---@param index integer
local function AddEntry(entries, action, ownerId, index)
    entries[#entries + 1] = {
        action = action, key = Menu_Data.GetActionKey(action),
        ownerId = ownerId, ownerIndex = index
    }
end

--- Whether `action` is a submenu scrolled with the mouse wheel.
---@param action Action?
---@return boolean
function Menu_Live.IsScroll(action)
    return Menu_Live.IsSubmenu(action) and not (action --[[@as Action]]).spread
end

--- Adds the live entries of `actions` (stored in menu `ownerId`) to `entries`.
---@param entries LiveEntry[]
---@param actions Action[]
---@param ownerId string
---@param visited table<string, boolean> the menus being walked, to skip loops
---@param depth integer
---@param flatten boolean? spread every submenu, scroll ones too (inside a scroll list)
local function AddEntries(entries, actions, ownerId, visited, depth, flatten)
    for index, action in ipairs(actions) do
        if Menu_Actions.IsActionAvailable(action) then
            if Menu_Live.IsSpread(action) or (flatten and Menu_Live.IsSubmenu(action)) then
                local child = Menu_Data.GetMenu(action.menu)
                if child and not visited[child.id] and depth < MAX_DEPTH then
                    visited[child.id] = true
                    AddEntries(entries, child.actions, child.id, visited, depth + 1, flatten)
                    visited[child.id] = nil
                end
            else
                AddEntry(entries, action, ownerId, index)
            end
        end
    end
end

--- The live entries of `menu` (see the header).
---@param menu Menu?
---@return LiveEntry[]
function Menu_Live.GetEntries(menu)
    local entries = {}
    if menu then AddEntries(entries, menu.actions, menu.id, { [menu.id] = true }, 0) end
    return entries
end

--- The menu as the player sees it right now: `entries`, their `actions`, and the center's
--- `quickAction` while it can fire.
---@param menu Menu
---@return LiveMenu
function Menu_Live.Build(menu)
    local entries = Menu_Live.GetEntries(menu)
    local actions = {}
    for index, entry in ipairs(entries) do actions[index] = entry.action end
    local quickAction = Menu_Data.GetQuickAction(menu)
    if quickAction and not Menu_Actions.IsActionAvailable(quickAction) then quickAction = nil end
    return { id = menu.id, name = menu.name, entries = entries, actions = actions, quickAction = quickAction }
end

--- What a scroll submenu cycles through: the submenu's actions, with every submenu inside it
--- spread in place (a scroll list is always flat). It's empty when `action` isn't one, or has
--- nothing to show.
---@param action Action?
---@return Action[]
function Menu_Live.GetScrollActions(action)
    local actions = {}
    local menu = Menu_Live.IsScroll(action) and Menu_Data.GetMenu((action --[[@as Action]]).menu)
    if not menu then return actions end
    local entries = {}
    AddEntries(entries, menu.actions, menu.id, { [menu.id] = true }, 0, true)
    for index, entry in ipairs(entries) do actions[index] = entry.action end
    return actions
end

--- Whether submenu `menuId` has submenus of its own (spread into its scroll list when it's one).
---@param menuId string
---@return boolean
function Menu_Live.HasSubmenus(menuId)
    local menu = Menu_Data.GetMenu(menuId)
    for _, action in ipairs(menu and menu.actions or {}) do
        if Menu_Live.IsSubmenu(action) then return true end
    end
    return false
end

--- The action a wedge shows for `action`. A scroll submenu shows its current action.
---@param action Action
---@param scrollIndex integer? its position in its scroll list (1 when out of range)
---@return Action
function Menu_Live.GetShownAction(action, scrollIndex)
    if not Menu_Live.IsScroll(action) then return action end
    local children = Menu_Live.GetScrollActions(action)
    return children[scrollIndex or 1] or children[1] or action
end

--- The action stored action `index` of `menu` shows, at its remembered scroll position.
---@param menu Menu
---@param index integer
---@return Action
function Menu_Live.GetStoredShownAction(menu, index)
    return Menu_Live.GetShownAction(menu.actions[index], Menu_Data.GetScrollIndex(menu.id, index))
end

--- How many actions a spread submenu adds to its menu right now.
---@param action Action?
---@return integer
function Menu_Live.CountSpread(action)
    if not Menu_Live.IsSpread(action) then return 0 end
    return #Menu_Live.GetEntries(Menu_Data.GetMenu((action --[[@as Action]]).menu))
end

--- Whether menu `menuId` has any action shown right now (a submenu hides while it has none).
---@param menuId string
---@param depth integer? how deep in submenus this is asked from, to stop loops
---@return boolean
function Menu_Live.HasShownActions(menuId, depth)
    local menu = Menu_Data.GetMenu(menuId)
    if not menu or (depth or 0) > MAX_DEPTH then return false end
    for _, action in ipairs(menu.actions) do
        if Menu_Actions.IsActionAvailable(action, (depth or 0) + 1) then return true end
    end
    return false
end
