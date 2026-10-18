--[[
    Ring_Secure (see Snippets.lua): a menu's secure button, and the attributes the snippets read,
    from its live menu (Ring_Live). That's its actions per wedge (Ring_Actions), scroll submenus,
    target marker copies (Mark Target Markers On), Cursor + Focus, and its keybind's parts.
    Keys.lua binds the keybinds collected here, and Rebuild.lua runs it, out of combat.
]]

local env = select(2, ...)
local Config = env.Config
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Live = env.AX_Modules:Import("@\\Ring\\Live")
local Ring_Display = env.AX_Modules:Import("@\\Ring\\Display")
local Ring_Crossbar = env.AX_Modules:Import("@\\Ring\\Crossbar")
local Ring_Secure = env.AX_Modules:Import("@\\Ring\\Secure")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")

-- A target marker's copies, after its suffix. PRE_CLICK spells them out too.
local TAP_SUFFIX = "M"   -- marks the mouseover (a tap)
local FOCUS_SUFFIX = "F" -- marks your focus, then clears it (Cursor + Focus)

-- Modifiers a binding string can start with, in WoW's order (ALT-CTRL-SHIFT-KEY).
local MODIFIERS = { "ALT-", "CTRL-", "SHIFT-", "META-" }

-- Menus that can steal your focus (Cursor + Focus) hold only these, because any other action
-- couldn't clear it after firing. Last Used and First Action fire one of the menu's own wedges.
-- Scroll submenus may hold target markers and Close.
local STEAL_KINDS = {
    [Ring_Kinds.Kind.TargetMarker] = true, [Ring_Kinds.Kind.Close] = true,
    [Ring_Kinds.Kind.LastUsed] = true, [Ring_Kinds.Kind.First] = true,
}
local STEAL_CHILD_KINDS = { [Ring_Kinds.Kind.TargetMarker] = true, [Ring_Kinds.Kind.Close] = true }

--- A live menu as Ring_Secure keeps it (Private.ringsById).
---@class SecureLiveRing : LiveRing
---@field markerSuffixes { suffix: string, id: number }[] its target marker slots, for AimMarkers
---@field cursorMarkers boolean Mark Target Markers On is Cursor (either kind)
---@field canStealFocus boolean it steals your focus (Cursor + Focus, only target markers)

---@class PendingBinding
---@field key string the keybind
---@field button string the menu button's name
---@field scope string the menu's Ring_Data.Scope

-- The menus' keybinds, filled by SetupRing and bound by Keys.lua (account keybinds first).
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
---@param ringId string
---@return Button
local function GetRingButton(ringId)
    local button = Private.buttonsById[ringId]
    if not button then
        button = CreateFrame("Button", "RLRM_Ring_" .. ringId, UIParent, "SecureActionButtonTemplate") --[[@as Button]]
        button:SetSize(1, 1)
        button:EnableMouse(false)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("useOnKeyDown", false)
        SecureHandlerWrapScript(button, "OnClick", Private.Controller, Private.PRE_CLICK)
        Private.buttonsById[ringId] = button
    end
    return button
end

--- Sets up the target marker copies of the action `slice` just applied under `suffix`, for
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
---@param live SecureLiveRing
---@param suffix string
---@param slice Slice
local function SetupMarkerSlot(button, live, suffix, slice)
    local isMarker = Ring_Kinds.IsUnitMarker(slice)
    if isMarker then table.insert(live.markerSuffixes, { suffix = suffix, id = slice.id }) end
    local tap = isMarker and live.cursorMarkers
    Ring_Kinds.SetAttribute(button, "type", suffix .. TAP_SUFFIX, (tap and "macro") or nil)
    Ring_Kinds.SetAttribute(button, "macrotext", suffix .. TAP_SUFFIX,
        (tap and Ring_Kinds.GetTargetMarkerText(slice.id, "mouseover")) or nil)

    local focusText
    if live.canStealFocus and slice.kind == Ring_Kinds.Kind.TargetMarker then
        local mark = (isMarker and Ring_Kinds.GetTargetMarkerText(slice.id, "focus"))
            or ("/click " .. Private.ClearMarkers:GetName())
        focusText = mark .. "\n" .. Private.FOCUS_CLEAR_TEXT
    elseif live.canStealFocus and slice.kind == Ring_Kinds.Kind.Close then
        -- A Close in a scroll submenu is picked like any action (PRE_CLICK only checks wedges for
        -- Close), so its copy just clears the focus.
        focusText = Private.FOCUS_CLEAR_TEXT
    end
    Ring_Kinds.SetAttribute(button, "type", suffix .. FOCUS_SUFFIX, (focusText and "macro") or nil)
    Ring_Kinds.SetAttribute(button, "macrotext", suffix .. FOCUS_SUFFIX, focusText)
end

--- Whether `slice` lets its menu steal your focus, and whether it marks a unit.
---@param slice Slice
---@return boolean allowed
---@return boolean marks
local function CheckStealSlice(slice)
    if STEAL_KINDS[slice.kind] then return true, Ring_Kinds.IsUnitMarker(slice) end
    if not Ring_Live.IsScroll(slice) then return false, false end
    -- An empty one fires nothing when picked, so it couldn't clear the focus either.
    local children = Ring_Live.GetScrollSlices(slice)
    if #children == 0 then return false, false end
    local marks = false
    for _, child in ipairs(children) do
        if not STEAL_CHILD_KINDS[child.kind] then return false, false end
        marks = marks or Ring_Kinds.IsUnitMarker(child)
    end
    return true, marks
end

--- Whether live menu `live` can steal your focus (with Cursor + Focus). That's when it marks units
--- and every action it can fire (the quick action too) is a target marker or fires nothing. Asked
--- before its slots are set up, because SetupMarkerSlot gives them focus copies only then.
---@param live SecureLiveRing
---@return boolean
local function CanStealFocus(live)
    local marks = false
    local function Allows(slice)
        local ok, slotMarks = CheckStealSlice(slice)
        marks = marks or slotMarks
        return ok
    end
    if live.quickSlice and not Allows(live.quickSlice) then return false end
    for _, slice in ipairs(live.slices) do
        if not Allows(slice) then return false end
    end
    return marks
end

--- Sets up wedge `index` as a scroll submenu when it is one: its action count, the shown action,
--- and every action under "sN_C". Out of combat.
---@param live SecureLiveRing
---@param button Button
---@param index integer
---@param slice Slice
---@return boolean isScroll
local function SetupScrollSlice(live, button, index, slice)
    local entry = live.entries[index]
    button:SetAttribute(Ring_Secure.Attribute.ScrollCount .. index, nil)
    button:SetAttribute(Ring_Secure.Attribute.Scroll .. index, nil)

    if not (Ring_Live.IsScroll(slice) and Ring_Data.GetRing(slice.ring)) then return false end

    -- Only the submenu's shown actions can be scrolled to.
    local children = Ring_Live.GetScrollSlices(slice)
    local count = #children
    local current = Ring_Data.GetScrollIndex(entry.ownerId, entry.ownerIndex)
    if current > count then current = 1 end
    button:SetAttribute(Ring_Secure.Attribute.ScrollCount .. index, count)
    button:SetAttribute(Ring_Secure.Attribute.Scroll .. index, (count > 0 and current) or nil)
    for childIndex, childSlice in ipairs(children) do
        local suffix = "s" .. index .. "_" .. childIndex
        Ring_Actions.ApplySliceSuffix(button, suffix, childSlice)
        SetupMarkerSlot(button, live, suffix, childSlice)
    end
    return true
end

--- The live index of the entry whose key is `key`, or nil.
---@param live SecureLiveRing
---@param key string?
---@return integer?
local function FindEntry(live, key)
    for index, entry in ipairs(live.entries) do
        if entry.key == key then return index end
    end
end

--- Sets up menu `ring`'s secure button for its live menu, and queues its keybind. Out of combat.
---@param ring Ring
function Private.SetupRing(ring)
    local button = GetRingButton(ring.id)
    local live = Ring_Live.Build(ring) --[[@as SecureLiveRing]]
    local count = #live.slices
    live.markerSuffixes = {} -- target marker slots { suffix, id } (SetupMarkerSlot), for AimMarkers
    -- Mark Target Markers On, read once for its slots. Cursor (either kind), and whether this menu
    -- steals your focus (Cursor + Focus, and a menu of only target markers).
    local cursor, steal = Private.GetMarkerMode()
    live.cursorMarkers = cursor
    live.canStealFocus = steal and CanStealFocus(live)
    Private.ForgetAimedMarkers(button)

    button:SetAttribute(Ring_Secure.Attribute.Id, ring.id)
    button:SetAttribute(Ring_Secure.Attribute.Count, count)
    button:SetAttribute(Ring_Secure.Attribute.Deadzone, Ring_Data.GetDeadzone())
    button:SetAttribute(Ring_Secure.Attribute.ProbeSize, Ring_Data.GetProbeSize())
    -- Select From = Menu Center: the fixed menu's center (UIParent units, like START_X/Y).
    local centerX, centerY
    if Ring_Display.IsSelectFromMenu() then centerX, centerY = Ring_Display.GetFixedCenter() end
    button:SetAttribute(Ring_Secure.Attribute.Origin, (centerX and Ring_Secure.ORIGIN_MENU) or nil)
    button:SetAttribute(Ring_Secure.Attribute.CenterX, centerX)
    button:SetAttribute(Ring_Secure.Attribute.CenterY, centerY)
    -- The live index of the last used action, found by its identity, for Last Used actions. Nil
    -- before any was used, or while it's hidden. PRE_CLICK keeps it current.
    button:SetAttribute(Ring_Secure.Attribute.Last, FindEntry(live, Ring_Data.GetLastUsedKey(ring.id)))
    -- The live index of the first wedge that fires something, for First Actions (nil when none).
    local firstIndex
    for index, slice in ipairs(live.slices) do
        if Ring_Kinds.CanBeFirst(slice) then firstIndex = index break end
    end
    button:SetAttribute(Ring_Secure.Attribute.First, firstIndex)

    if live.quickSlice then
        -- A tap-only quick action. Its attributes live under "sQ", and the snippet sends a tap there.
        Ring_Actions.ApplySliceSuffix(button, "s" .. Private.QUICK_SUFFIX, live.quickSlice)
        SetupMarkerSlot(button, live, "s" .. Private.QUICK_SUFFIX, live.quickSlice)
        button:SetAttribute(Ring_Secure.Attribute.Quick, Private.QUICK_SUFFIX)
    else
        -- A single action sits in the center (Ring_View), so a tap fires it. Otherwise a tap fires
        -- nothing.
        button:SetAttribute(Ring_Secure.Attribute.Quick, (count == 1 and 1) or nil)
    end

    local hasScroll = false
    for index, slice in ipairs(live.slices) do
        Ring_Actions.ApplySlice(button, index, slice)
        SetupMarkerSlot(button, live, "s" .. index, slice)
        if SetupScrollSlice(live, button, index, slice) then hasScroll = true end
    end
    button:SetAttribute(Ring_Secure.Attribute.HasScroll, hasScroll or nil)
    -- Cursor + Focus: the press steals your focus (PRE_CLICK), and every way out clears it.
    local canSteal = live.canStealFocus
    button:SetAttribute(Ring_Secure.Attribute.StealFocus, canSteal or nil)
    button:SetAttribute(Ring_Secure.Attribute.Aimed, nil)
    -- The steal is a focus action on the mouseover (the reticle's unit, with a controller), not a
    -- macro. A crossbar slot or stick combo opens the menu from a macro, and a macro run from
    -- inside a macro does nothing.
    Ring_Kinds.SetAttribute(button, "type", Ring_Secure.Click.FocusSteal, (canSteal and "focus") or nil)
    Ring_Kinds.SetAttribute(button, "unit", Ring_Secure.Click.FocusSteal, (canSteal and "mouseover") or nil)
    Ring_Kinds.SetAttribute(button, "type", Ring_Secure.Click.FocusClear, (canSteal and "macro") or nil)
    Ring_Kinds.SetAttribute(button, "macrotext", Ring_Secure.Click.FocusClear,
        (canSteal and Private.FOCUS_CLEAR_TEXT) or nil)

    Private.ringsById[ring.id] = live
    local binding, scope = Ring_Data.GetBinding(ring.id)
    button:SetAttribute(Ring_Secure.Attribute.KeyMods, GetModifierPrefix(binding))
    -- The key it's on, without modifiers (for a controller combo, its plain button or stick). It's
    -- left to the menu while open, so pressed again, it reaches the menu (which closes).
    local keyBase = binding and (Ring_Crossbar.GetPlainButton(binding) or binding:match("[^%-]+$") or binding)
    button:SetAttribute(Ring_Secure.Attribute.KeyBase, keyBase or nil)
    button:SetAttribute(Ring_Secure.Attribute.RightClick, (Config.Get(Config.Key.RightClickDismiss) and true) or nil)
    -- Menu Style, always Relaxed in WoW Forever's gamepad UI (A picks, B closes). Menus rebuild when
    -- the UI switches (Rebuild.lua).
    local relaxed = env.IsGamepadUI() or Config.Get(Config.Key.MenuStyle) == env.Enum.MenuStyle.Relaxed
    button:SetAttribute(Ring_Secure.Attribute.Relaxed, relaxed or nil)
    button:SetAttribute(Ring_Secure.Attribute.Flick, (Config.Get(Config.Key.FlickToSelect) and true) or nil)
    -- A crossbar slot isn't a key. Its macro on the crossbar opens the menu (Ring_Crossbar).
    if binding and not Ring_Crossbar.IsSlot(binding) and (count > 0 or live.quickSlice) then
        table.insert(Private.pendingBindings, { key = binding, button = button:GetName(), scope = scope })
    end
end
