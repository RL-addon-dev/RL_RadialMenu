--[[
    Controller combos (WoW Forever's gamepad UI): a menu on "LT + A", a D-pad direction, or
    "LT + R3".

    In that UI, LT / RT aren't Shift / Ctrl: they're bound to GAMEPADLEFTMOD / GAMEPADRIGHTMOD,
    which pick the active crossbar (none: top, LT: left, RT: right, both: bottom), and the face
    buttons and D-pad are bound to GAMEPADACTIONBUTTON1-8, which press that bar's slot. So these
    combos aren't keys. One is saved as "PAD:<side>:<button>": the modifiers held (TOP: none,
    LEFT: LT, RIGHT: RT, BOTH) and the button pressed ("PAD:LEFT:PAD1" = LT + A,
    "PAD:TOP:PADDUP" = D-pad up, "PAD:BOTH:PADRSTICK" = LT + RT + R3).

    Crossbar slots (a face button or D-pad direction): the menu opens through an account macro
    placed in the slot, on the current page:

        #rlrm
        /click RLRM_Ring_<id> Gamepad 1
        /click RLRM_Ring_<id> Gamepad

    (a controller's open: Ring_Secure). The "#rlrm" line marks the macros this file manages, so
    hand-made ones are never touched. Some slots are reserved for the gamepad UI's own actions
    (the top bar's face buttons: jump, interact ...): those can't be used. Reconcile (each
    rebuild, out of combat) keeps the macros in step with the menus: renamed with their menu;
    removed from the crossbar and deleted once their menu has no slot or is gone.

    L3 / R3 (plain, or with LT / RT / both) aren't crossbar slots: the stick is bound to a
    dispatcher that opens the menu of the modifiers held (Ring_Secure: Keys.lua, STICK_CLICK).

    LB / RB (the targeting modifiers) are reserved for the gamepad UI's targeting: never used.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Crossbar = env.AX_Modules:New("@\\Ring\\Crossbar")

local PREFIX = "PAD:"
local ACTION_BUTTONS = 8 -- GAMEPADACTIONBUTTON1-8: the slots of a crossbar
-- Each side's crossbar, and the bindings held for it.
local BARS = { TOP = "topBar", LEFT = "leftBar", RIGHT = "rightBar", BOTH = "bottomBar" }
local MODIFIERS = { TOP = {}, LEFT = { "GAMEPADLEFTMOD" }, RIGHT = { "GAMEPADRIGHTMOD" }, BOTH = { "GAMEPADLEFTMOD", "GAMEPADRIGHTMOD" } }
local CROSSBAR_MODIFIERS = MODIFIERS.BOTH
local TARGETING_MODIFIERS = { "GAMEPADLEFTTARGETMODIFIER", "GAMEPADRIGHTTARGETMODIFIER" }
local STICKS = { PADLSTICK = true, PADRSTICK = true }

local MACRO_MARKER = "#rlrm"
local MACRO_BODY = MACRO_MARKER .. "\n/click RLRM_Ring_%s Gamepad 1\n/click RLRM_Ring_%s Gamepad"
local MACRO_RING_PATTERN = "^" .. MACRO_MARKER .. "\n/click RLRM_Ring_(%d+) Gamepad"
local MACRO_NAME_LENGTH = 16 -- longest macro name the game takes
-- The macros' icons, one per menu in turn: the same icon in five colours.
local MACRO_ICONS = { 4630454, 4630455, 4630456, 4630457, 4630458 }



-- Combos

--- @return string|nil side "TOP" | "LEFT" | "RIGHT" | "BOTH", for a combo ("PAD:LEFT:PAD1")
--- @return string|nil button "PAD1", "PADDUP", "PADRSTICK" ...
local function Parse(key)
    local side, button = tostring(key):match("^PAD:(%u+):(%w+)$")
    if BARS[side] then return side, button end
end

--- Whether `key` is a controller combo ("PAD:LEFT:PAD1"), not a real key.
function Ring_Crossbar.IsCombo(key)
    return Parse(key) ~= nil
end

--- Whether `key` is a crossbar slot combo (a face button or D-pad direction: opened by a macro).
function Ring_Crossbar.IsSlot(key)
    local side, button = Parse(key)
    return side ~= nil and not STICKS[button]
end

--- @return string|nil side, string|nil stick for an L3 / R3 combo ("PAD:LEFT:PADRSTICK")
function Ring_Crossbar.ParseStick(key)
    local side, button = Parse(key)
    if STICKS[button] then return side, button end
end

--- The button a combo is pressed with on its own (no modifier), or the stick of an L3 / R3 combo:
--- left to the menu while it's open (Ring_Secure: "ring-keybase"). Nil for other keys.
function Ring_Crossbar.GetPlainButton(key)
    local side, button = Parse(key)
    if side == "TOP" or STICKS[button] then return button end
end

--- The keys bound to `action` (Forever's crossbar bindings live in a binding context: mode 1).
local function GetKeys(action)
    return { GetBindingKey(action, 1) }
end

--- The (first) button bound to gamepad UI binding `action` ("GAMEPADLEFTMOD": LT ...), or nil.
function Ring_Crossbar.GetBoundKey(action)
    return GetKeys(action)[1]
end

local function IsBoundTo(button, actions)
    for _, action in ipairs(actions) do
        if tIndexOf(GetKeys(action), button) then return true end
    end
    return false
end

--- The button index (GetGamePadState().buttons) of crossbar modifier `side` ("LEFT": LT), or nil.
function Ring_Crossbar.GetModifierIndex(side)
    local key = GetKeys(MODIFIERS[side][1])[1]
    local index = key and C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(key)
    return index and index + 1
end

--- The crossbar slot (GAMEPADACTIONBUTTON<index>) `button` presses, or nil.
local function GetSlotIndex(button)
    for index = 1, ACTION_BUTTONS do
        if tIndexOf(GetKeys("GAMEPADACTIONBUTTON" .. index), button) then return index end
    end
end

local function GetPageUnit()
    local frame = _G["GamepadMainActionBarFrame"]
    return frame and frame.PageUnit
end

--- The page slot ID (the same on every page) `button` presses on `side`'s crossbar, or nil.
local function GetSlotId(side, button)
    local index = GetSlotIndex(button)
    local pageUnit = GetPageUnit()
    local bar = index and pageUnit and pageUnit.actionBars and pageUnit.actionBars[BARS[side]]
    local slotButton = bar and bar:GetActionButtonByIndex(index)
    return slotButton and slotButton.GetGamepadPageUnitSlotID and slotButton:GetGamepadPageUnitSlotID()
end

--- What a controller button pressed during keybind capture binds, with `held` the buttons held
--- ([button] = true, `button` included).
--- @return string|nil key the combo ("PAD:LEFT:PAD1"), or `button` itself (R3 ... alone)
--- @return string|nil problem why nothing is bound: "Held" (a modifier: keep listening),
---     "Targeting" (LB / RB), "OnlyModifiers" (another button held), "NotSlot" (LT / RT with a
---     button that takes none), "Reserved" (a slot the gamepad UI keeps: A alone ...)
function Ring_Crossbar.FromPress(button, held)
    if IsBoundTo(button, CROSSBAR_MODIFIERS) or IsBoundTo(button, TARGETING_MODIFIERS) then return nil, "Held" end
    for other in pairs(held) do
        if other ~= button then
            if IsBoundTo(other, TARGETING_MODIFIERS) then return nil, "Targeting" end
            if not IsBoundTo(other, CROSSBAR_MODIFIERS) then return nil, "OnlyModifiers" end
        end
    end
    local function IsHeld(key) return held[key] or IsKeyDown(key) end
    local function IsDown(action) return IsHeld(GetKeys(action)[1] or "") end
    local left, right = IsDown("GAMEPADLEFTMOD"), IsDown("GAMEPADRIGHTMOD")
    local side = (left and right and "BOTH") or (left and "LEFT") or (right and "RIGHT") or "TOP"

    if not STICKS[button] then
        local slotId = GetSlotId(side, button)
        local util = _G["GamepadActionBarBindingUtil"]
        if not (slotId and util) then
            if side ~= "TOP" then return nil, "NotSlot" end
            return button -- not a crossbar button: bound as itself
        end
        if not util.IsBindablePageUnitSlotID(slotId) then return nil, "Reserved" end
    end
    return PREFIX .. side .. ":" .. button
end

--- "LT + A" (with the controller's icons where the client draws them): the buttons the combo's
--- modifiers are on right now, and its button.
function Ring_Crossbar.GetDisplayText(key)
    local side, button = Parse(key)
    if not side then return tostring(key) end
    local parts = {}
    for _, action in ipairs(MODIFIERS[side]) do
        local bound = GetKeys(action)[1]
        parts[#parts + 1] = bound and GetBindingText(bound) or action
    end
    parts[#parts + 1] = GetBindingText(button)
    return table.concat(parts, " + ")
end



-- The crossbar slot

--- The action storage slot slot combo `key` presses on the current crossbar page, or nil (no
--- gamepad UI, or a reserved slot).
local function GetStorageSlot(key)
    local side, button = Parse(key)
    local pageUnit = GetPageUnit()
    local util = _G["GamepadActionBarBindingUtil"]
    local slotId = side and GetSlotId(side, button)
    if not (slotId and pageUnit and util) then return nil end
    return util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(pageUnit:GetCurrentPage(), slotId)
end

--- Every crossbar action storage slot (all pages).
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

--- Index of the account macro this file made for menu `ringId`, or nil.
local function FindMacro(ringId)
    local numAccount = GetNumMacros()
    for index = 1, numAccount do
        local body = GetMacroBody(index)
        if body and body:match(MACRO_RING_PATTERN) == tostring(ringId) then return index end
    end
end

--- "RM <menu name>", cut to the macro name limit without splitting a character.
local function GetMacroName(ring)
    local name = "RM " .. (ring.name or "")
    if #name <= MACRO_NAME_LENGTH then return name end
    return (name:sub(1, MACRO_NAME_LENGTH):gsub("[\192-\255][\128-\191]*$", ""))
end

-- New macros' icons: the palette colours in turn. The count of macros made so far is saved
-- account-wide (the macros are account macros; settings resets keep it), so the colours follow
-- the palette's order whatever was deleted since.
local MADE_KEY = "CrossbarMacrosMade"

local function GetMacrosMade()
    local db = env.Config.DBGlobalPersistent
    return db and tonumber(db:GetVariable(MADE_KEY)) or 0
end

--- The next macro's icon (counted once it's made: CountMacroMade).
local function NextMacroIcon()
    return MACRO_ICONS[GetMacrosMade() % #MACRO_ICONS + 1]
end

local function CountMacroMade()
    local db = env.Config.DBGlobalPersistent
    if db then db:SetVariable(MADE_KEY, GetMacrosMade() + 1) end
end

--- Removes macro `index` from every crossbar slot holding it.
local function ClearFromCrossbar(macroIndex)
    local util = _G["GamepadActionBarBindingUtil"]
    if not util then return end
    ForEachStorageSlot(function(slot)
        local actionType, id = GetActionInfo(slot)
        if actionType == "macro" and id == macroIndex then util.ClearActionFromGamepadSlot(slot) end
    end)
end

--- The menu's macro: the existing one (renamed if its menu was), else a new one.
--- @return number|nil index nil when the account macros are full
local function EnsureMacro(ring)
    local name = GetMacroName(ring)
    local index = FindMacro(ring.id)
    if index then
        local currentName, icon, body = GetMacroInfo(index)
        if currentName ~= name then index = EditMacro(index, name, icon, body) end
        return index
    end
    local ok, created = pcall(CreateMacro, name, NextMacroIcon(), MACRO_BODY:format(ring.id, ring.id), false)
    if not (ok and created) then return nil end
    CountMacroMade()
    return created
end



-- Placing

--- What the slot `key` presses holds now, for the "replace it?" prompt: its name, or nil when
--- it's empty or already holds menu `ringId`'s macro.
function Ring_Crossbar.GetOccupant(ringId, key)
    local slot = GetStorageSlot(key)
    if not slot or not HasAction(slot) then return nil end
    local actionType, id = GetActionInfo(slot)
    if actionType == "macro" then
        if id == FindMacro(ringId) then return nil end
        return (GetMacroInfo(id))
    elseif actionType == "spell" then
        return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) or actionType
    elseif actionType == "item" then
        return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or actionType
    end
    return GetActionText(slot) or actionType
end

Ring_Crossbar.PlaceError = {
    Combat = "combat",       -- macros and action slots can't change in combat
    NoCrossbar = "nocrossbar", -- no gamepad UI crossbar to place it on
    Full = "full",           -- the account macros are full
}

--- Puts menu `ringId`'s macro (made if needed) on the slot `key` presses, on the current
--- crossbar page, and takes it off any other crossbar slot. Out of combat.
--- @return boolean ok
--- @return string|nil reason Ring_Crossbar.PlaceError
function Ring_Crossbar.Place(ringId, key)
    if InCombatLockdown() then return false, Ring_Crossbar.PlaceError.Combat end
    local ring = Ring_Data.GetRing(ringId)
    local slot = GetStorageSlot(key)
    local util = _G["GamepadActionBarBindingUtil"]
    if not (ring and slot and util) then return false, Ring_Crossbar.PlaceError.NoCrossbar end
    local macroIndex = EnsureMacro(ring)
    if not macroIndex then return false, Ring_Crossbar.PlaceError.Full end
    ClearFromCrossbar(macroIndex)
    util.AssignActionToGamepadStandardSlot(slot, PickupMacro, macroIndex)
    return true
end



-- Keeping macros in step with the menus

--- Renames the macros of menus that were renamed, and removes (from the crossbar, then deletes)
--- those whose menu has no crossbar slot any more, or no longer exists. Menus that live elsewhere
--- (another class's or character's) keep theirs. Out of combat (Ring_Secure's rebuild).
function Ring_Crossbar.Reconcile()
    if InCombatLockdown() then return end
    -- The menus first: renaming or deleting a macro re-sorts the list, so each is looked up again.
    local ringIds = {}
    for index = 1, GetNumMacros() do
        local body = GetMacroBody(index)
        local ringId = body and body:match(MACRO_RING_PATTERN)
        if ringId then ringIds[#ringIds + 1] = ringId end
    end
    for _, ringId in ipairs(ringIds) do
        local index = FindMacro(ringId) -- nil: a duplicate already handled
        local ring = Ring_Data.GetRing(ringId)
        if index and ring and Ring_Crossbar.IsSlot(Ring_Data.GetBinding(ringId)) then
            local name = GetMacroName(ring)
            local currentName, icon, body = GetMacroInfo(index)
            if currentName ~= name then EditMacro(index, name, icon, body) end
        elseif index and (ring or not Ring_Data.GetElsewhereRing(ringId)) then
            ClearFromCrossbar(index)
            DeleteMacro(index)
        end
    end
end
