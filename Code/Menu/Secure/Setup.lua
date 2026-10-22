--[[
    Menu_Secure (see Snippets.lua): a menu's secure button, and the attributes the snippets read,
    from its live menu (Menu_Live). That's its actions per wedge (Menu_Actions), scroll submenus,
    target marker copies (Mark Target Markers On), Cursor + Focus, and its keybind's parts.
    Keys.lua binds the keybinds collected here, and Rebuild.lua runs it, out of combat.
]]

local env = select(2, ...)
local Config = env.Config
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Actions = env.AX_Modules:Import("@\\Menu\\Actions")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Live = env.AX_Modules:Import("@\\Menu\\Live")
local Menu_Display = env.AX_Modules:Import("@\\Menu\\Display")
local Menu_Crossbar = env.AX_Modules:Import("@\\Menu\\Crossbar")
local Menu_Secure = env.AX_Modules:Import("@\\Menu\\Secure")
local Private = env.AX_Modules:Import("@\\Menu\\Secure\\Private")
local Utils_ConsolePort = env.AX_Modules:Import("@\\Utils\\ConsolePort")

-- A target marker's copies, after its suffix. PRE_CLICK spells them out too.
local TAP_SUFFIX = "M"   -- marks the mouseover (a tap)
local FOCUS_SUFFIX = "F" -- marks your focus, then clears it (Cursor + Focus)

-- Modifiers a binding string can start with, in WoW's order (ALT-CTRL-SHIFT-KEY).
local MODIFIERS = { "ALT-", "CTRL-", "SHIFT-", "META-" }

-- Menus that can steal your focus (Cursor + Focus) hold only these, because any other action
-- couldn't clear it after firing. Last Used and First Action fire one of the menu's own wedges.
-- Scroll submenus may hold target markers and Close.
local STEAL_KINDS = {
    [Menu_Kinds.Kind.TargetMarker] = true, [Menu_Kinds.Kind.Close] = true,
    [Menu_Kinds.Kind.LastUsed] = true, [Menu_Kinds.Kind.First] = true,
}
local STEAL_CHILD_KINDS = { [Menu_Kinds.Kind.TargetMarker] = true, [Menu_Kinds.Kind.Close] = true }

--- A live menu as Menu_Secure keeps it (Private.menusById).
---@class SecureLiveMenu : LiveMenu
---@field markerSuffixes { suffix: string, id: number }[] its target marker slots, for AimMarkers
---@field cursorMarkers boolean Mark Target Markers On is Cursor (either kind)
---@field canStealFocus boolean it steals your focus (Cursor + Focus, only target markers)

---@class PendingBinding
---@field key string the keybind
---@field button string the menu button's name
---@field scope string the menu's Menu_Data.Scope

-- The menus' keybinds, filled by SetupMenu and bound by Keys.lua (account keybinds first).
---@type PendingBinding[]
Private.pendingBindings = {}

--- Mark Target Markers On, as two answers. The first says whether markers mark the unit under the
--- mouse (Cursor or Cursor + Focus). The second says whether menus of only target markers steal
--- your focus for it (Cursor + Focus).
---@return boolean cursor
---@return boolean steal
function Private.GetMarkerMode()
    local value = Config.Get(Config.Key.TargetMarkerUnit)
    local steal = value == env.Enum.TargetMarkerUnit.CursorFocus
    return steal or value == env.Enum.TargetMarkerUnit.Cursor, steal
end

--- The modifier part of a keybind ("CTRL-" for "CTRL-SPACE", "ALT-SHIFT-" for "ALT-SHIFT-F"), or
--- nil without modifiers. They're held with the key, so the bindings made while the menu is held
--- (right click, the wheel) need them too (PRE_CLICK).
---@param binding string?
---@return string?
local function GetModifierPrefix(binding)
    if not binding then return nil end
    local prefix, rest = "", binding
    for _, modifier in ipairs(MODIFIERS) do
        if rest:sub(1, #modifier) == modifier and #rest > #modifier then
            prefix = prefix .. modifier
            rest = rest:sub(#modifier + 1)
        end
    end
    return (prefix ~= "" and prefix) or nil
end

--- The menu's secure button, created on first use. Frames can't be destroyed, so it's reused.
---@param menuId string
---@return Button
local function GetMenuButton(menuId)
    local button = Private.buttonsById[menuId]
    if not button then
        button = CreateFrame("Button", "RLRM_" .. menuId, UIParent, "SecureActionButtonTemplate") --[[@as Button]]
        button:SetSize(1, 1)
        button:EnableMouse(false)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("useOnKeyDown", false)
        SecureHandlerWrapScript(button, "OnClick", Private.Controller, Private.PRE_CLICK)
        Private.buttonsById[menuId] = button
    end
    return button
end

--- Sets up the target marker copies of the action `action` just applied under `suffix`, for
--- Mark Target Markers On. Any other action's copies are cleared, so a copy never outlives its
--- marker. Out of combat.
---     - With Cursor, a target marker gets a tap copy ("<suffix>M") that marks the mouseover as
---       it fires. A tap leaves the mouse on the unit, so it works on any unit, in combat too, and
---       on your target when there's none. It's also listed for aiming (live.markerSuffixes,
---       AimMarkers in Callbacks.lua).
---     - In a menu that steals your focus (live.canStealFocus), target markers (Clear too) get a
---       copy that marks your focus (Clear clears every marker), then clears it ("<suffix>F").
---       Close gets one that only clears it.
---@param button Button
---@param live SecureLiveMenu
---@param suffix string
---@param action Action
local function SetupMarkerSlot(button, live, suffix, action)
    local isMarker = Menu_Kinds.IsUnitMarker(action)
    if isMarker then table.insert(live.markerSuffixes, { suffix = suffix, id = action.id }) end
    local tap = isMarker and live.cursorMarkers
    Menu_Kinds.SetSlotAttribute(button, "type", suffix .. TAP_SUFFIX, (tap and "macro") or nil)
    Menu_Kinds.SetSlotAttribute(button, "macrotext", suffix .. TAP_SUFFIX,
        (tap and Menu_Kinds.GetTargetMarkerText(action.id, "mouseover")) or nil)

    local focusText
    if live.canStealFocus and action.kind == Menu_Kinds.Kind.TargetMarker then
        local mark = (isMarker and Menu_Kinds.GetTargetMarkerText(action.id, "focus"))
            or ("/click " .. Private.ClearMarkers:GetName())
        focusText = mark .. "\n" .. Private.FOCUS_CLEAR_TEXT
    elseif live.canStealFocus and action.kind == Menu_Kinds.Kind.Close then
        -- A Close in a scroll submenu is picked like any action (PRE_CLICK only checks wedges for
        -- Close), so its copy just clears the focus.
        focusText = Private.FOCUS_CLEAR_TEXT
    end
    Menu_Kinds.SetSlotAttribute(button, "type", suffix .. FOCUS_SUFFIX, (focusText and "macro") or nil)
    Menu_Kinds.SetSlotAttribute(button, "macrotext", suffix .. FOCUS_SUFFIX, focusText)
end

--- Whether `action` lets its menu steal your focus, and whether it marks a unit.
---@param action Action
---@return boolean allowed
---@return boolean marks
local function CheckStealAction(action)
    if STEAL_KINDS[action.kind] then return true, Menu_Kinds.IsUnitMarker(action) end
    if not Menu_Live.IsScroll(action) then return false, false end
    -- An empty one fires nothing when picked, so it couldn't clear the focus either.
    local children = Menu_Live.GetScrollActions(action)
    if #children == 0 then return false, false end
    local marks = false
    for _, child in ipairs(children) do
        if not STEAL_CHILD_KINDS[child.kind] then return false, false end
        marks = marks or Menu_Kinds.IsUnitMarker(child)
    end
    return true, marks
end

--- Whether live menu `live` can steal your focus (with Cursor + Focus). That's when it marks units
--- and every action it can fire (the quick action too) is a target marker or fires nothing. Asked
--- before its slots are set up, because SetupMarkerSlot gives them focus copies only then.
---@param live SecureLiveMenu
---@return boolean
local function CanStealFocus(live)
    local marks = false
    local function Allows(action)
        local ok, slotMarks = CheckStealAction(action)
        marks = marks or slotMarks
        return ok
    end
    if live.quickAction and not Allows(live.quickAction) then return false end
    for _, action in ipairs(live.actions) do
        if not Allows(action) then return false end
    end
    return marks
end

--- Sets up wedge `index` as a scroll submenu when it is one: its action count, the shown action,
--- and every action under "sN_C". Out of combat.
---@param live SecureLiveMenu
---@param button Button
---@param index integer
---@param action Action
---@return boolean isScroll
local function SetupScrollAction(live, button, index, action)
    local entry = live.entries[index]
    button:SetAttribute(Menu_Secure.Attribute.ScrollCount .. index, nil)
    button:SetAttribute(Menu_Secure.Attribute.Scroll .. index, nil)

    if not (Menu_Live.IsScroll(action) and Menu_Data.GetMenu(action.menu)) then return false end

    -- Only the submenu's shown actions can be scrolled to.
    local children = Menu_Live.GetScrollActions(action)
    local count = #children
    local current = Menu_Data.GetScrollIndex(entry.ownerId, entry.ownerIndex)
    if current > count then current = 1 end
    button:SetAttribute(Menu_Secure.Attribute.ScrollCount .. index, count)
    button:SetAttribute(Menu_Secure.Attribute.Scroll .. index, (count > 0 and current) or nil)
    for childIndex, childAction in ipairs(children) do
        local suffix = "s" .. index .. "_" .. childIndex
        Menu_Actions.ApplyActionSuffix(button, suffix, childAction)
        SetupMarkerSlot(button, live, suffix, childAction)
    end
    return true
end

--- The live index of the entry whose key is `key`, or nil.
---@param live SecureLiveMenu
---@param key string?
---@return integer?
local function FindEntry(live, key)
    for index, entry in ipairs(live.entries) do
        if entry.key == key then return index end
    end
end

--- Sets up menu `menu`'s secure button for its live menu, and queues its keybind. Out of combat.
---@param menu Menu
function Private.SetupMenu(menu)
    local button = GetMenuButton(menu.id)
    local live = Menu_Live.Build(menu) --[[@as SecureLiveMenu]]
    local count = #live.actions
    live.markerSuffixes = {} -- target marker slots { suffix, id } (SetupMarkerSlot), for AimMarkers
    -- Mark Target Markers On, read once for its slots. Cursor (either kind), and whether this menu
    -- steals your focus (Cursor + Focus, and a menu of only target markers).
    local cursor, steal = Private.GetMarkerMode()
    live.cursorMarkers = cursor
    live.canStealFocus = steal and CanStealFocus(live)
    Private.ForgetAimedMarkers(button)

    button:SetAttribute(Menu_Secure.Attribute.Id, menu.id)
    button:SetAttribute(Menu_Secure.Attribute.Count, count)
    button:SetAttribute(Menu_Secure.Attribute.Deadzone, Menu_Data.GetDeadzone())
    button:SetAttribute(Menu_Secure.Attribute.ProbeSize, Menu_Data.GetProbeSize())
    -- Select From = Menu Center: the fixed menu's center (UIParent units, like START_X/Y).
    local centerX, centerY
    if Menu_Display.IsSelectFromMenu() then centerX, centerY = Menu_Display.GetFixedCenter() end
    button:SetAttribute(Menu_Secure.Attribute.Origin, (centerX and Menu_Secure.ORIGIN_MENU) or nil)
    button:SetAttribute(Menu_Secure.Attribute.CenterX, centerX)
    button:SetAttribute(Menu_Secure.Attribute.CenterY, centerY)
    -- The live index of the last used action, found by its identity, for Last Used actions. Nil
    -- before any was used, or while it's hidden. PRE_CLICK keeps it current.
    button:SetAttribute(Menu_Secure.Attribute.Last, FindEntry(live, Menu_Data.GetLastUsedKey(menu.id)))
    -- The live index of the first wedge that fires something, for First Actions (nil when none).
    local firstIndex
    for index, action in ipairs(live.actions) do
        if Menu_Kinds.CanBeFirst(action) then firstIndex = index break end
    end
    button:SetAttribute(Menu_Secure.Attribute.First, firstIndex)

    if live.quickAction then
        -- A tap-only quick action. Its attributes live under "sQ", and the snippet sends a tap there.
        Menu_Actions.ApplyActionSuffix(button, "s" .. Private.QUICK_SUFFIX, live.quickAction)
        SetupMarkerSlot(button, live, "s" .. Private.QUICK_SUFFIX, live.quickAction)
        button:SetAttribute(Menu_Secure.Attribute.Quick, Private.QUICK_SUFFIX)
    else
        -- A single action sits in the center (Menu_View), so a tap fires it. Otherwise a tap fires
        -- nothing.
        button:SetAttribute(Menu_Secure.Attribute.Quick, (count == 1 and 1) or nil)
    end

    local hasScroll = false
    for index, action in ipairs(live.actions) do
        Menu_Actions.ApplyAction(button, index, action)
        SetupMarkerSlot(button, live, "s" .. index, action)
        if SetupScrollAction(live, button, index, action) then hasScroll = true end
    end
    button:SetAttribute(Menu_Secure.Attribute.HasScroll, hasScroll or nil)
    -- Cursor + Focus: the press steals your focus (PRE_CLICK), and every way out clears it.
    local canSteal = live.canStealFocus
    button:SetAttribute(Menu_Secure.Attribute.StealFocus, canSteal or nil)
    button:SetAttribute(Menu_Secure.Attribute.Aimed, nil)
    -- The steal is a focus action on the mouseover (the reticle's unit, with a controller), not a
    -- macro. A crossbar slot or stick combo opens the menu from a macro, and a macro run from
    -- inside a macro does nothing.
    Menu_Kinds.SetSlotAttribute(button, "type", Menu_Secure.Click.FocusSteal, (canSteal and "focus") or nil)
    Menu_Kinds.SetSlotAttribute(button, "unit", Menu_Secure.Click.FocusSteal, (canSteal and "mouseover") or nil)
    Menu_Kinds.SetSlotAttribute(button, "type", Menu_Secure.Click.FocusClear, (canSteal and "macro") or nil)
    Menu_Kinds.SetSlotAttribute(button, "macrotext", Menu_Secure.Click.FocusClear,
        (canSteal and Private.FOCUS_CLEAR_TEXT) or nil)

    Private.menusById[menu.id] = live
    local binding, scope = Menu_Data.GetBinding(menu.id)
    button:SetAttribute(Menu_Secure.Attribute.KeyMods, GetModifierPrefix(binding))
    -- The key it's on, without modifiers (for a controller combo, its plain button or stick). It's
    -- left to the menu while open, so pressed again, it reaches the menu (which closes).
    local keyBase = binding and (Menu_Crossbar.GetPlainButton(binding) or binding:match("[^%-]+$") or binding)
    button:SetAttribute(Menu_Secure.Attribute.KeyBase, keyBase or nil)
    button:SetAttribute(Menu_Secure.Attribute.RightClick, (Config.Get(Config.Key.RightClickDismiss) and true) or nil)
    -- Menu Style, always Relaxed with a controller, in WoW Forever's gamepad UI or with ConsolePort
    -- (A picks, B closes). Menus rebuild when the UI switches (Rebuild.lua).
    local controller = env.IsGamepadUI() or Utils_ConsolePort.IsActive()
    local relaxed = controller or Config.Get(Config.Key.MenuStyle) == env.Enum.MenuStyle.Relaxed
    button:SetAttribute(Menu_Secure.Attribute.Relaxed, relaxed or nil)
    button:SetAttribute(Menu_Secure.Attribute.Flick, (Config.Get(Config.Key.FlickToSelect) and true) or nil)
    -- A crossbar slot isn't a key. Its macro on the crossbar opens the menu (Menu_Crossbar).
    if binding and not Menu_Crossbar.IsSlot(binding) and (count > 0 or live.quickAction) then
        table.insert(Private.pendingBindings, { key = binding, button = button:GetName(), scope = scope })
    end
end
