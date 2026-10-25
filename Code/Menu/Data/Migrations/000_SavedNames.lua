--[[
    The saved names followed the addon's terms: rings became menus, slices became actions,
    built-in menus became library menus, and an expanded submenu became a spread one.
        - Tables: Rings is Menus, ClassRings is ClassMenus, NextRingId is NextMenuId and
          LastUsedSlice is LastUsedAction. Other characters' copies (CharacterMenus) hold `menus`
          instead of `rings`.
        - A menu: `slices` is `actions` and `builtin` is `library`. The quick action is the action
          itself in `quickAction` (nil for an empty center), instead of quickAction = "custom" with
          the action in `quickSlice`.
        - A submenu action: its kind "ring" is "submenu", `ring` is `menu` and `expand` is
          `spread`. Its identity (Menu_Data.GetActionKey) changes with the kind, so saved keys
          ("ring:12") follow: Last Used, and library menus' remembered order and removed actions.
    An older quickAction (an index into the actions, or "last") stays as it is, for
    001_CenterQuickSlot. This runs before the older migrations, which read these new names.
    The names are written out here, not taken from the code, so this keeps doing the same thing
    whatever the code calls them later.
]]

local env = select(2, ...)
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")

local type, pairs, ipairs = type, pairs, ipairs

--- Moves table `old` of `stored` to `new`. When both exist, `new` keeps its own entries.
---@param stored table
---@param old string
---@param new string
local function MoveTable(stored, old, new)
    if type(stored[old]) ~= "table" then return end
    if type(stored[new]) ~= "table" then
        stored[new] = stored[old]
    else
        for key, value in pairs(stored[old]) do
            if stored[new][key] == nil then stored[new][key] = value end
        end
    end
    stored[old] = nil
end

--- An action key in the new kind's name.
---@param key any
---@return any
local function ConvertKey(key)
    if type(key) == "string" and key:sub(1, 5) == "ring:" then return "submenu:" .. key:sub(6) end
    return key
end

---@param action any
local function ConvertAction(action)
    if type(action) ~= "table" or action.kind ~= "ring" then return end
    action.kind, action.menu, action.spread = "submenu", action.ring, action.expand
    action.ring, action.expand = nil, nil
end

---@param menu any
local function ConvertMenu(menu)
    if type(menu) ~= "table" then return end
    if menu.actions == nil then menu.actions = menu.slices end
    menu.slices = nil
    if menu.quickAction == "custom" then
        menu.quickAction = menu.quickSlice
    elseif menu.quickAction == "none" then
        menu.quickAction = nil
    end
    menu.quickSlice = nil
    if menu.library == nil then menu.library = menu.builtin end
    menu.builtin = nil

    for _, action in ipairs(type(menu.actions) == "table" and menu.actions or {}) do
        ConvertAction(action)
    end
    ConvertAction(menu.quickAction)
    for index, key in ipairs(type(menu.order) == "table" and menu.order or {}) do
        menu.order[index] = ConvertKey(key)
    end
    for _, entry in ipairs(type(menu.removed) == "table" and menu.removed or {}) do
        if type(entry) == "table" then entry.key = ConvertKey(entry.key) end
    end
end

--- Every menu in `menus` ([id] = menu).
---@param menus any
local function ConvertMenus(menus)
    for _, menu in pairs(type(menus) == "table" and menus or {}) do
        ConvertMenu(menu)
    end
end

Private.RegisterMigration({
    flag = "SavedNamesAccount",
    db   = Private.MigrationDB.Account,
    run  = function(stored)
        MoveTable(stored, "Rings", "Menus")
        MoveTable(stored, "ClassRings", "ClassMenus")
        if stored.NextMenuId == nil then stored.NextMenuId = stored.NextRingId end
        stored.NextRingId = nil

        ConvertMenus(stored.Menus)
        -- Class menus are account-wide, so this converts every class's.
        for _, menus in pairs(type(stored.ClassMenus) == "table" and stored.ClassMenus or {}) do
            ConvertMenus(menus)
        end
        -- Other characters' copies. Their own saved menus convert when they log in.
        for _, snapshot in pairs(type(stored.CharacterMenus) == "table" and stored.CharacterMenus or {}) do
            if type(snapshot) == "table" then
                MoveTable(snapshot, "rings", "menus")
                ConvertMenus(snapshot.menus)
            end
        end
    end,
})

Private.RegisterMigration({
    flag = "SavedNamesCharacter",
    db   = Private.MigrationDB.Character,
    run  = function(stored)
        MoveTable(stored, "Rings", "Menus")
        ConvertMenus(stored.Menus)
        MoveTable(stored, "LastUsedSlice", "LastUsedAction")
        for id, key in pairs(type(stored.LastUsedAction) == "table" and stored.LastUsedAction or {}) do
            stored.LastUsedAction[id] = ConvertKey(key)
        end
    end,
})
