--[[
    Controller combos (WoW Forever's gamepad UI), like a menu on "LT + A", a D-pad direction, or
    "LT + R3".

    In that UI, LT and RT aren't Shift and Ctrl. They're bound to GAMEPADLEFTMOD and
    GAMEPADRIGHTMOD, which pick the active crossbar (top with none held, left with LT, right with
    RT, bottom with both), and the face buttons and D-pad are bound to GAMEPADACTIONBUTTON1-8,
    which press that bar's slot. So these combos aren't keys. One is saved as
    "PAD:<side>:<button>", with the modifiers held as the side (Menu_Crossbar.Side) and the button
    pressed. For example, "PAD:LEFT:PAD1" is LT + A, "PAD:TOP:PADDUP" is D-pad up, and
    "PAD:BOTH:PADRSTICK" is LT + RT + R3.

    A crossbar slot (a face button or D-pad direction) opens its menu through an account macro
    placed in the slot, on the current page, which does a controller's open (Menu_Secure):

        #rlrm
        /click RLRM_<id> Gamepad 1
        /click RLRM_<id> Gamepad

    The "#rlrm" line marks the macros this file manages, so hand-made ones are never touched. Some
    slots are reserved for the gamepad UI's own actions (the top bar's face buttons, like jump and
    interact), and those can't be used. Reconcile (each rebuild, out of combat) keeps the macros in
    step with the menus. They're renamed with their menu, and removed from the crossbar and deleted
    once their menu has no slot or is gone. Macros from before the buttons were renamed click
    RLRM_Ring_<id>, and Reconcile rewrites them.

    L3 and R3 (plain, or with LT, RT or both) aren't crossbar slots. The stick is bound to a
    dispatcher that opens the menu of the modifiers held (Menu_Secure's Keys.lua, STICK_CLICK).

    LB and RB (the targeting modifiers) are reserved for the gamepad UI's targeting, and never used.
]]

local env = select(2, ...)
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Crossbar = env.AX_Modules:New("@\\Menu\\Crossbar")

-- A combo's side: the crossbar modifiers held (saved data, never renamed). Menu_Secure's
-- STICK_CLICK snippet spells these out too.
Menu_Crossbar.Side = Utils_Standard.Strict({
    Top   = "TOP",   -- none
    Left  = "LEFT",  -- LT
    Right = "RIGHT", -- RT
    Both  = "BOTH",  -- LT and RT
}, "crossbar side")
Menu_Crossbar.SIDE_ORDER = {
    Menu_Crossbar.Side.Top, Menu_Crossbar.Side.Left, Menu_Crossbar.Side.Right, Menu_Crossbar.Side.Both,
}

-- The gamepad UI's bindings this file reads.
local LEFT_MODIFIER, RIGHT_MODIFIER = "GAMEPADLEFTMOD", "GAMEPADRIGHTMOD"
local LEFT_TARGETING, RIGHT_TARGETING = "GAMEPADLEFTTARGETMODIFIER", "GAMEPADRIGHTTARGETMODIFIER"
local TARGETING_MODIFIERS = { LEFT_TARGETING, RIGHT_TARGETING }
-- The same, for the settings' keybind help (Menu_Crossbar.GetBoundKey).
Menu_Crossbar.Binding = Utils_Standard.Strict({
    LeftModifier   = LEFT_MODIFIER,   -- LT, the left crossbar
    RightModifier  = RIGHT_MODIFIER,  -- RT, the right crossbar
    LeftTargeting  = LEFT_TARGETING,  -- LB
    RightTargeting = RIGHT_TARGETING, -- RB
}, "gamepad binding")
local ACTION_BUTTON = "GAMEPADACTIONBUTTON" -- 1 to ACTION_BUTTONS, a crossbar's slots
local ACTION_BUTTONS = 8

local PREFIX = "PAD:"
local PAD_BUTTON_PREFIX = "PAD" -- every controller button's key starts with it (PAD1, PADDUP...)
-- Each side's crossbar, and the modifiers held for it.
local BARS = {
    [Menu_Crossbar.Side.Top]   = "topBar",
    [Menu_Crossbar.Side.Left]  = "leftBar",
    [Menu_Crossbar.Side.Right] = "rightBar",
    [Menu_Crossbar.Side.Both]  = "bottomBar",
}
local MODIFIERS = {
    [Menu_Crossbar.Side.Top]   = {},
    [Menu_Crossbar.Side.Left]  = { LEFT_MODIFIER },
    [Menu_Crossbar.Side.Right] = { RIGHT_MODIFIER },
    [Menu_Crossbar.Side.Both]  = { LEFT_MODIFIER, RIGHT_MODIFIER },
}
local CROSSBAR_MODIFIERS = MODIFIERS[Menu_Crossbar.Side.Both]
local STICKS = { PADLSTICK = true, PADRSTICK = true }

local MACRO_MARKER = "#rlrm"
local MACRO_BODY = MACRO_MARKER .. "\n/click RLRM_%s Gamepad 1\n/click RLRM_%s Gamepad"
local MACRO_MENU_PATTERN = "^" .. MACRO_MARKER .. "\n/click RLRM_(%d+) Gamepad"
local OLD_MACRO_MENU_PATTERN = "^" .. MACRO_MARKER .. "\n/click RLRM_Ring_(%d+) Gamepad" -- before the rename
local MACRO_NAME_LENGTH = 16 -- the longest macro name the game takes
-- The macros' icons, one per menu in turn: the same icon in five colours.
local MACRO_ICONS = { 4630454, 4630455, 4630456, 4630457, 4630458 }
-- How many macros were made so far, saved account-wide (DBGlobalPersistent). See NextMacroIcon.
local MADE_KEY = "CrossbarMacrosMade"

-- Why a controller press can't be a keybind (Menu_Crossbar.FromPress). The values end the
-- locale keys "Config - Menus - Keybind - Crossbar - <value>" (Held has none, it keeps listening).
Menu_Crossbar.PressProblem = Utils_Standard.Strict({
    Held          = "Held",
    Targeting     = "Targeting",
    OnlyModifiers = "OnlyModifiers",
    NotSlot       = "NotSlot",
    Reserved      = "Reserved",
}, "controller press problem")

-- Why Menu_Crossbar.Place didn't place the macro.
Menu_Crossbar.PlaceError = Utils_Standard.Strict({
    Combat     = "combat",     -- macros and action slots can't change in combat
    NoCrossbar = "nocrossbar", -- no gamepad UI crossbar to place it on
    Full       = "full",       -- the account macros are full
}, "crossbar place error")



-- Combos

--- A combo's side and button, or nil for anything else.
---@param key any
---@return string? side a Menu_Crossbar.Side value
---@return string? button "PAD1", "PADDUP", "PADRSTICK"...
local function Parse(key)
    local side, button = tostring(key):match("^PAD:(%u+):(%w+)$")
    if BARS[side] then return side, button end
end

--- Whether `key` is a controller combo ("PAD:LEFT:PAD1"), not a real key.
---@param key any
---@return boolean
function Menu_Crossbar.IsCombo(key)
    return Parse(key) ~= nil
end

--- Whether `key` is a crossbar slot combo (a face button or D-pad direction), opened by a macro.
---@param key any
---@return boolean
function Menu_Crossbar.IsSlot(key)
    local side, button = Parse(key)
    return side ~= nil and not STICKS[button]
end

--- The side and stick of an L3 or R3 combo ("PAD:LEFT:PADRSTICK"), or nil for anything else.
---@param key any
---@return string? side a Menu_Crossbar.Side value
---@return string? stick "PADLSTICK" or "PADRSTICK"
function Menu_Crossbar.ParseStick(key)
    local side, button = Parse(key)
    if STICKS[button] then return side, button end
end

--- Whether `key` is a controller button (PAD1, PADDUP, PADRSTICK...), with or without modifiers.
---@param key string
---@return boolean
function Menu_Crossbar.IsPadButton(key)
    local base = key:match("[^%-]+$") or key -- the key without its modifiers (not NUMPAD1)
    return base:sub(1, #PAD_BUTTON_PREFIX) == PAD_BUTTON_PREFIX
end

--- The button a combo is pressed with on its own (no modifier), or the stick of an L3 or R3
--- combo. It's left to the menu while it's open (Menu_Secure's "menu-keybase"). Nil for other keys.
---@param key any
---@return string?
function Menu_Crossbar.GetPlainButton(key)
    local side, button = Parse(key)
    if side == Menu_Crossbar.Side.Top or STICKS[button] then return button end
end

--- The keys bound to gamepad UI binding `action`. Forever's crossbar bindings live in a binding
--- context, mode 1.
---@param action string
---@return string[]
local function GetKeys(action)
    -- The editor's annotations (Retail's) lack the mode parameter.
    ---@diagnostic disable-next-line: redundant-parameter
    return { GetBindingKey(action, 1) }
end

--- The first button bound to gamepad UI binding `action` (GAMEPADLEFTMOD is LT...), or nil.
---@param action string
---@return string?
function Menu_Crossbar.GetBoundKey(action)
    return GetKeys(action)[1]
end

--- Whether `button` is bound to any of `actions`.
---@param button string
---@param actions string[]
---@return boolean
local function IsBoundTo(button, actions)
    for _, action in ipairs(actions) do
        if tIndexOf(GetKeys(action), button) then return true end
    end
    return false
end

--- The button index (in GetGamePadState().buttons) of crossbar modifier `side` (LT for LEFT), or nil.
---@param side string Menu_Crossbar.Side.Left or Right
---@return integer?
function Menu_Crossbar.GetModifierIndex(side)
    local key = GetKeys(MODIFIERS[side][1])[1]
    local index = key and C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(key)
    return index and index + 1
end

--- The crossbar slot (GAMEPADACTIONBUTTON<index>) `button` presses, or nil.
---@param button string
---@return integer?
local function GetSlotIndex(button)
    for index = 1, ACTION_BUTTONS do
        if tIndexOf(GetKeys(ACTION_BUTTON .. index), button) then return index end
    end
end

--- The gamepad UI's crossbar pages, or nil without that UI.
local function GetPageUnit()
    local frame = _G["GamepadMainActionBarFrame"]
    return frame and frame.PageUnit
end

--- The page slot ID (the same on every page) `button` presses on `side`'s crossbar, or nil.
---@param side string a Menu_Crossbar.Side value
---@param button string
---@return number?
local function GetSlotId(side, button)
    local index = GetSlotIndex(button)
    local pageUnit = GetPageUnit()
    local bar = index and pageUnit and pageUnit.actionBars and pageUnit.actionBars[BARS[side]]
    local slotButton = bar and bar:GetActionButtonByIndex(index)
    return slotButton and slotButton.GetGamepadPageUnitSlotID and slotButton:GetGamepadPageUnitSlotID()
end

--- What a controller button pressed during keybind capture binds, with `held` the buttons held
--- (`button` included).
---@param button string
---@param held table<string, boolean>
---@return string? key the combo ("PAD:LEFT:PAD1"), or `button` itself (R3 alone...)
---@return string? problem why nothing is bound, one of these.
---     Held means it's a modifier, so keep listening.
---     Targeting means LB or RB is held.
---     OnlyModifiers means another button is held.
---     NotSlot means LT or RT is held with a button that takes none.
---     Reserved means a slot the gamepad UI keeps (A alone...).
function Menu_Crossbar.FromPress(button, held)
    if IsBoundTo(button, CROSSBAR_MODIFIERS) or IsBoundTo(button, TARGETING_MODIFIERS) then
        return nil, Menu_Crossbar.PressProblem.Held
    end
    for other in pairs(held) do
        if other ~= button then
            if IsBoundTo(other, TARGETING_MODIFIERS) then return nil, Menu_Crossbar.PressProblem.Targeting end
            if not IsBoundTo(other, CROSSBAR_MODIFIERS) then return nil, Menu_Crossbar.PressProblem.OnlyModifiers end
        end
    end
    local function IsHeld(key) return held[key] or IsKeyDown(key) end
    local function IsDown(action) return IsHeld(GetKeys(action)[1] or "") end
    local left, right = IsDown(LEFT_MODIFIER), IsDown(RIGHT_MODIFIER)
    local side = (left and right and Menu_Crossbar.Side.Both) or (left and Menu_Crossbar.Side.Left)
        or (right and Menu_Crossbar.Side.Right) or Menu_Crossbar.Side.Top

    if not STICKS[button] then
        local slotId = GetSlotId(side, button)
        local util = _G["GamepadActionBarBindingUtil"]
        if not (slotId and util) then
            if side ~= Menu_Crossbar.Side.Top then return nil, Menu_Crossbar.PressProblem.NotSlot end
            return button -- not a crossbar button, so it's bound as itself
        end
        if not util.IsBindablePageUnitSlotID(slotId) then return nil, Menu_Crossbar.PressProblem.Reserved end
    end
    return PREFIX .. side .. ":" .. button
end

--- A combo as text, like "LT + A" (with the controller's icons where the client draws them): the
--- buttons its modifiers are on right now, and its button.
---@param key any
---@return string
function Menu_Crossbar.GetDisplayText(key)
    local side, button = Parse(key)
    if not side then return tostring(key) end
    local parts = {}
    for _, action in ipairs(MODIFIERS[side]) do
        local bound = GetKeys(action)[1]
        parts[#parts + 1] = (bound and GetBindingText(bound)) or action
    end
    parts[#parts + 1] = GetBindingText(button)
    return table.concat(parts, " + ")
end



-- The crossbar slot

--- The action storage slot combo `key` presses on the current crossbar page, or nil (no gamepad
--- UI, or a reserved slot).
---@param key any
---@return number?
local function GetStorageSlot(key)
    local side, button = Parse(key)
    local pageUnit = GetPageUnit()
    local util = _G["GamepadActionBarBindingUtil"]
    local slotId = side and GetSlotId(side, button --[[@as string]])
    if not (slotId and pageUnit and util) then return nil end
    return util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(pageUnit:GetCurrentPage(), slotId)
end

--- Calls `callback(slot)` for every crossbar action storage slot (all pages).
---@param callback fun(slot: number)
local function ForEachStorageSlot(callback)
    local gamepadUI = _G["C_GamepadUI"]
    if not (gamepadUI and gamepadUI.GetFirstGamepadActionStorageSlotIndex) then return end
    local slot = gamepadUI.GetFirstGamepadActionStorageSlotIndex()
    while slot and gamepadUI.IsValidGamepadActionStorageSlotIndex(slot) do
        callback(slot)
        slot = slot + 1
    end
end



-- Macros (account macros only)

--- The menu id a macro this file made opens, from its body, or nil for any other macro.
---@param body string?
---@return string? menuId
---@return boolean old the body is from before the buttons were renamed
local function ParseMacro(body)
    if not body then return nil, false end
    local menuId = body:match(MACRO_MENU_PATTERN)
    if menuId then return menuId, false end
    menuId = body:match(OLD_MACRO_MENU_PATTERN)
    return menuId, menuId ~= nil
end

--- The index of the account macro this file made for menu `menuId`, or nil.
---@param menuId string|number
---@return integer?
local function FindMacro(menuId)
    local numAccount = GetNumMacros()
    for index = 1, numAccount do
        if ParseMacro(GetMacroBody(index)) == tostring(menuId) then return index end
    end
end

--- "RM <menu name>", cut to the macro name limit without splitting a character.
---@param menu Menu
---@return string
local function GetMacroName(menu)
    local name = "RM " .. (menu.name or "")
    if #name <= MACRO_NAME_LENGTH then return name end
    return (name:sub(1, MACRO_NAME_LENGTH):gsub("[\192-\255][\128-\191]*$", ""))
end

--- How many macros were made so far.
---@return integer
local function GetMacrosMade()
    local db = env.Config.DBGlobalPersistent
    return (db and tonumber(db:GetVariable(MADE_KEY))) or 0
end

--- The next macro's icon, the palette colours in turn. The count of macros made so far is saved
--- account-wide (the macros are account macros, and settings resets keep it), so the colours
--- follow the palette's order whatever was deleted since. It's counted once the macro is made
--- (CountMacroMade).
---@return number
local function NextMacroIcon()
    return MACRO_ICONS[GetMacrosMade() % #MACRO_ICONS + 1]
end

local function CountMacroMade()
    local db = env.Config.DBGlobalPersistent
    if db then db:SetVariable(MADE_KEY, GetMacrosMade() + 1) end
end

--- Removes macro `macroIndex` from every crossbar slot holding it.
---@param macroIndex integer
local function ClearFromCrossbar(macroIndex)
    local util = _G["GamepadActionBarBindingUtil"]
    if not util then return end
    ForEachStorageSlot(function(slot)
        local actionType, id = GetActionInfo(slot)
        if actionType == "macro" and id == macroIndex then util.ClearActionFromGamepadSlot(slot) end
    end)
end

--- The menu's macro: the existing one (renamed if its menu was), else a new one.
---@param menu Menu
---@return integer? index nil when the account macros are full
local function EnsureMacro(menu)
    local name = GetMacroName(menu)
    local index = FindMacro(menu.id)
    if index then
        local currentName, icon, body = GetMacroInfo(index)
        if currentName ~= name then index = EditMacro(index, name, icon, body) end
        return index
    end
    local ok, created = pcall(CreateMacro, name, NextMacroIcon(), MACRO_BODY:format(menu.id, menu.id), false)
    if not (ok and created) then return nil end
    CountMacroMade()
    return created
end



-- Placing

--- What the slot `key` presses holds now, for the "replace it?" prompt. That's its name, or nil
--- when it's empty or already holds menu `menuId`'s macro.
---@param menuId string
---@param key string
---@return string?
function Menu_Crossbar.GetOccupant(menuId, key)
    local slot = GetStorageSlot(key)
    if not slot or not HasAction(slot) then return nil end
    local actionType, id = GetActionInfo(slot)
    if actionType == "macro" then
        if id == FindMacro(menuId) then return nil end
        return (GetMacroInfo(id))
    elseif actionType == "spell" then
        return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) or actionType
    elseif actionType == "item" then
        return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or actionType
    end
    return GetActionText(slot) or actionType
end

--- Puts menu `menuId`'s macro (made if needed) on the slot `key` presses, on the current crossbar
--- page, and takes it off any other crossbar slot. Out of combat.
---@param menuId string
---@param key string
---@return boolean ok
---@return string? reason a Menu_Crossbar.PlaceError value
function Menu_Crossbar.Place(menuId, key)
    if InCombatLockdown() then return false, Menu_Crossbar.PlaceError.Combat end
    local menu = Menu_Data.GetMenu(menuId)
    local slot = GetStorageSlot(key)
    local util = _G["GamepadActionBarBindingUtil"]
    if not (menu and slot and util) then return false, Menu_Crossbar.PlaceError.NoCrossbar end
    local macroIndex = EnsureMacro(menu)
    if not macroIndex then return false, Menu_Crossbar.PlaceError.Full end
    ClearFromCrossbar(macroIndex)
    util.AssignActionToGamepadStandardSlot(slot, PickupMacro, macroIndex)
    return true
end



-- Keeping macros in step with the menus

--- Renames the macros of menus that were renamed, and removes (from the crossbar, then deletes)
--- those whose menu has no crossbar slot any more, or no longer exists. Menus that live elsewhere
--- (another class's or character's) keep theirs. Out of combat (Menu_Secure's rebuild).
function Menu_Crossbar.Reconcile()
    if InCombatLockdown() then return end
    -- The menus first, because renaming or deleting a macro re-sorts the list, so each is looked
    -- up again. An old body is rewritten on the way, which keeps the name and so the order.
    local menuIds = {}
    for index = 1, GetNumMacros() do
        local menuId, old = ParseMacro(GetMacroBody(index))
        if old then
            local name, icon = GetMacroInfo(index)
            EditMacro(index, name, icon, MACRO_BODY:format(menuId, menuId))
        end
        if menuId then menuIds[#menuIds + 1] = menuId end
    end
    for _, menuId in ipairs(menuIds) do
        local index = FindMacro(menuId) -- nil for a duplicate already handled
        local menu = Menu_Data.GetMenu(menuId)
        if index and menu and Menu_Crossbar.IsSlot(Menu_Data.GetBinding(menuId)) then
            local name = GetMacroName(menu)
            local currentName, icon, body = GetMacroInfo(index)
            if currentName ~= name then EditMacro(index, name, icon, body) end
        elseif index and (menu or not Menu_Data.GetElsewhereMenu(menuId)) then
            ClearFromCrossbar(index)
            DeleteMacro(index)
        end
    end
end
