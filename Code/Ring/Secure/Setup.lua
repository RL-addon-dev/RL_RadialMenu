--[[
    Ring_Secure (see Snippets.lua): a menu's secure button and the attributes the snippets read,
    from its live ring (Ring_Live): its actions per wedge (Ring_Actions), scroll submenus, target
    marker copies (Mark Target Markers On), Cursor + Focus, and its keybind's parts. Keys.lua binds
    the keybinds collected here; Rebuild.lua runs it, out of combat.
]]

local env = select(2, ...)
local Config = env.Config
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Live = env.AX_Modules:Import("@\\Ring\\Live")
local Ring_Display = env.AX_Modules:Import("@\\Ring\\Display")
local Ring_Crossbar = env.AX_Modules:Import("@\\Ring\\Crossbar")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")

local ClearMarkers = Private.ClearMarkers
local FOCUS_STEAL, FOCUS_STEAL_TEXT = Private.FOCUS_STEAL, Private.FOCUS_STEAL_TEXT
local FOCUS_CLEAR, FOCUS_CLEAR_TEXT = Private.FOCUS_CLEAR, Private.FOCUS_CLEAR_TEXT
local QUICK_SUFFIX = Private.QUICK_SUFFIX
local ringsById, buttonsById = Private.ringsById, Private.buttonsById

local TAP_SUFFIX = "M" -- a target marker's tap copy ("<suffix>M"; PRE_CLICK spells it out)
local FOCUS_SUFFIX = "F" -- a target marker's stolen focus copy ("<suffix>F"; PRE_CLICK spells it out)

-- The menus' keybinds, filled by SetupRing, bound by Keys.lua (account keybinds first).
local pendingBindings = {}
Private.pendingBindings = pendingBindings

--- Mark Target Markers On: the unit under the mouse (Cursor or Cursor + Focus), and whether menus
--- of only target markers steal your focus for it (Cursor + Focus).
local function GetMarkerMode()
    local value = Config.Get(Config.Key.TargetMarkerUnit)
    local steal = value == env.Enum.TargetMarkerUnit.CursorFocus
    return steal or value == env.Enum.TargetMarkerUnit.Cursor, steal
end

Private.GetMarkerMode = GetMarkerMode

-- Modifiers a binding string can start with, in WoW's order (ALT-CTRL-SHIFT-KEY).
local MODIFIERS = { "ALT-", "CTRL-", "SHIFT-", "META-" }

--- The modifier part of a keybind ("CTRL-" for "CTRL-SPACE", "ALT-SHIFT-" for "ALT-SHIFT-F"), or
--- nil without modifiers: held with the key, so the mouse bindings while held need it too
--- (PRE_CLICK: right click, wheel).
local function GetModifierPrefix(binding)
    if not binding then return nil end
    local prefix, rest = "", binding
    for _, modifier in ipairs(MODIFIERS) do
        if rest:sub(1, #modifier) == modifier and #rest > #modifier then
            prefix = prefix .. modifier
            rest = rest:sub(#modifier + 1)
        end
    end
    return prefix ~= "" and prefix or nil
end

--- The ring's secure button, created on first use (frames can't be destroyed, so it's reused).
local function GetRingButton(ringId)
    local button = buttonsById[ringId]
    if not button then
        button = CreateFrame("Button", "RLRM_Ring_" .. ringId, UIParent, "SecureActionButtonTemplate")
        button:SetSize(1, 1)
        button:EnableMouse(false)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("useOnKeyDown", false)
        SecureHandlerWrapScript(button, "OnClick", Private.Controller, Private.PRE_CLICK)
        buttonsById[ringId] = button
    end
    return button
end

--- Cursor, for slot `suffix` just applied with `slice`. A target marker slot gets a tap copy
--- ("<suffix>M") that marks the mouseover as it fires (a tap leaves the mouse on the unit, so any
--- unit, in combat too; else your target), and is listed for aiming (live.markerSuffixes,
--- AimMarkers). In a menu that steals your focus (live.canStealFocus), target markers (Clear too)
--- also get a copy that marks your focus (Clear: clears every marker) and then clears it
--- ("<suffix>F"); Close gets one that only clears it. Any other slot's copies are cleared, so a
--- copy never outlives its marker. Out of combat.
local function SetupMarkerSlot(button, live, suffix, slice)
    local isMarker = Ring_Kinds.IsUnitMarker(slice)
    if isMarker then table.insert(live.markerSuffixes, { suffix = suffix, id = slice.id }) end
    local tap = isMarker and live.cursorMarkers
    button:SetAttribute("*type-" .. suffix .. TAP_SUFFIX, tap and "macro" or nil)
    button:SetAttribute("*macrotext-" .. suffix .. TAP_SUFFIX, tap and Ring_Kinds.GetTargetMarkerText(slice.id, "mouseover") or nil)

    local steal = live.canStealFocus
    local focusText
    if steal and slice.kind == Ring_Kinds.Kind.TargetMarker then
        focusText = (isMarker and Ring_Kinds.GetTargetMarkerText(slice.id, "focus") or "/click " .. ClearMarkers:GetName())
            .. "\n" .. FOCUS_CLEAR_TEXT
    elseif steal and slice.kind == Ring_Kinds.Kind.Close then
        -- A Close in a scroll submenu is picked like any action (PRE_CLICK only checks wedges for
        -- Close): its copy just clears the focus.
        focusText = FOCUS_CLEAR_TEXT
    end
    button:SetAttribute("*type-" .. suffix .. FOCUS_SUFFIX, focusText and "macro" or nil)
    button:SetAttribute("*macrotext-" .. suffix .. FOCUS_SUFFIX, focusText)
end

-- Menus that can steal your focus (Cursor + Focus) hold only these: any other action couldn't
-- clear it after firing. Last Used and First Action fire one of the menu's own wedges;
-- submenus that scroll may hold target markers and Close.
local STEAL_KINDS = { targetmarker = true, close = true, lastused = true, first = true }
local STEAL_CHILD_KINDS = { targetmarker = true, close = true }

--- Whether `slice` lets its menu steal your focus, and whether it marks a unit.
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

--- Whether live ring `live` can steal your focus (with Cursor + Focus): it marks units, and every
--- action it can fire (the quick action too) is a target marker or fires nothing. Before its slots
--- are set up (SetupMarkerSlot gives them focus copies only then).
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

--- Nested ring (scroll) slice attributes. Returns true if the slice is a nested ring.
--- Must be called out of combat.
local function SetupNestedSlice(live, button, index, slice)
    local entry = live.entries[index]
    button:SetAttribute("ring-scrollcount-" .. index, nil)
    button:SetAttribute("ring-scroll-" .. index, nil)

    if not (Ring_Live.IsScroll(slice) and Ring_Data.GetRing(slice.ring)) then return false end

    -- Only the submenu's shown actions can be scrolled to.
    local children = Ring_Live.GetScrollSlices(slice)
    local count = #children
    local current = Ring_Data.GetScrollIndex(entry.ownerId, entry.ownerIndex)
    if current > count then current = 1 end
    button:SetAttribute("ring-scrollcount-" .. index, count)
    button:SetAttribute("ring-scroll-" .. index, count > 0 and current or nil)
    for childIndex, childSlice in ipairs(children) do
        local suffix = "s" .. index .. "_" .. childIndex
        Ring_Actions.ApplySliceSuffix(button, suffix, childSlice)
        SetupMarkerSlot(button, live, suffix, childSlice)
    end
    return true
end

--- Must be called out of combat.
local function SetupRing(ring)
    local button = GetRingButton(ring.id)
    local live = Ring_Live.Build(ring)
    local count = #live.slices
    live.markerSuffixes = {} -- target marker slots { suffix, id } (SetupMarkerSlot), for AimMarkers
    -- Mark Target Markers On, read once for its slots: Cursor (either kind), and whether this menu
    -- steals your focus (Cursor + Focus, and a menu of only target markers).
    local cursor, steal = GetMarkerMode()
    live.cursorMarkers = cursor
    live.canStealFocus = steal and CanStealFocus(live)
    Private.ForgetAimedMarkers(button)

    button:SetAttribute("ring-id", ring.id)
    button:SetAttribute("ring-count", count)
    button:SetAttribute("ring-deadzone", Ring_Data.GetDeadzone())
    button:SetAttribute("ring-probe", Ring_Data.GetProbeSize())
    -- Select From = Menu Center: the fixed menu's center (UIParent units, like START_X/Y).
    local centerX, centerY
    if Ring_Display.IsSelectFromMenu() then centerX, centerY = Ring_Display.GetFixedCenter() end
    button:SetAttribute("ring-origin", centerX and "menu" or nil)
    button:SetAttribute("ring-centerx", centerX)
    button:SetAttribute("ring-centery", centerY)
    -- The last used action -> live index (nil before any, or while it's hidden), found by slice
    -- identity, for Last Used actions (PRE_CLICK keeps it current).
    local lastIndex
    local lastKey = Ring_Data.GetLastUsedKey(ring.id)
    for index, entry in ipairs(live.entries) do
        if entry.key == lastKey then lastIndex = index break end
    end
    button:SetAttribute("ring-last", lastIndex)
    -- The first wedge that fires something -> live index, for First Actions (nil when none).
    local firstIndex
    for index, slice in ipairs(live.slices) do
        if Ring_Kinds.CanBeFirst(slice) then firstIndex = index break end
    end
    button:SetAttribute("ring-first", firstIndex)

    if live.quickSlice then
        -- Tap-only quick action: its attributes live under "sQ"; the snippet redirects a tap there.
        Ring_Actions.ApplySliceSuffix(button, "s" .. QUICK_SUFFIX, live.quickSlice)
        SetupMarkerSlot(button, live, "s" .. QUICK_SUFFIX, live.quickSlice)
        button:SetAttribute("ring-quick", QUICK_SUFFIX)
    else
        -- A single slice sits in the center (Ring_View), so a tap fires it; else a tap fires nothing.
        button:SetAttribute("ring-quick", count == 1 and 1 or nil)
    end

    local hasScroll = false
    for index, slice in ipairs(live.slices) do
        Ring_Actions.ApplySlice(button, index, slice)
        SetupMarkerSlot(button, live, "s" .. index, slice)
        if SetupNestedSlice(live, button, index, slice) then hasScroll = true end
    end
    button:SetAttribute("ring-hasscroll", hasScroll or nil)
    -- Cursor + Focus: the press steals your focus (PRE_CLICK), every way out clears it.
    local canSteal = live.canStealFocus
    button:SetAttribute("ring-stealfocus", canSteal or nil)
    button:SetAttribute("ring-aimed", nil)
    button:SetAttribute("*type-" .. FOCUS_STEAL, canSteal and "macro" or nil)
    button:SetAttribute("*macrotext-" .. FOCUS_STEAL, canSteal and FOCUS_STEAL_TEXT or nil)
    button:SetAttribute("*type-" .. FOCUS_CLEAR, canSteal and "macro" or nil)
    button:SetAttribute("*macrotext-" .. FOCUS_CLEAR, canSteal and FOCUS_CLEAR_TEXT or nil)

    ringsById[ring.id] = live
    local binding, scope = Ring_Data.GetBinding(ring.id)
    button:SetAttribute("ring-keymods", GetModifierPrefix(binding))
    -- The key it's on, without modifiers (a controller combo: its plain button or stick), left to
    -- the menu while open: pressed again, it reaches the menu (which closes).
    local keyBase = binding and (Ring_Crossbar.GetPlainButton(binding) or binding:match("[^%-]+$") or binding)
    button:SetAttribute("ring-keybase", keyBase or nil)
    button:SetAttribute("ring-rightclick", Config.Get(Config.Key.RightClickDismiss) and true or nil)
    -- Menu Style; always Relaxed in WoW Forever's gamepad UI (A picks, B closes). Menus rebuild
    -- when the UI switches (Rebuild.lua).
    local relaxed = env.IsGamepadUI() or Config.Get(Config.Key.MenuStyle) == env.Enum.MenuStyle.Relaxed
    button:SetAttribute("ring-relaxed", relaxed or nil)
    button:SetAttribute("ring-flick", Config.Get(Config.Key.FlickToSelect) and true or nil)
    -- A crossbar slot isn't a key: its macro on the crossbar opens the menu (Ring_Crossbar).
    if binding and not Ring_Crossbar.IsSlot(binding) and (count > 0 or live.quickSlice) then
        pendingBindings[#pendingBindings + 1] = { key = binding, button = button:GetName(), scope = scope }
    end
end

Private.SetupRing = SetupRing
