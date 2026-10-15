--[[
    Secure ring controller (works in combat).

    Each keybound ring is a hidden SecureActionButton bound with an override binding and
    registered for AnyDown + AnyUp. Its OnClick is wrapped by a restricted snippet:

      key down  record cursor start, place the center probe under the cursor
                (secure auto-hide fires as soon as the cursor leaves it), open view,
                cancel the click so nothing fires.
      key up    selection from the cursor's offset from the key-down spot (or, with Select From =
                Menu Center, from the fixed menu's center):
                  outside deadzone           -> slice by angle
                  inside, probe still shown  -> quick action (cursor never left center)
                  inside, probe hidden       -> cancel
                The chosen slice fires by redirecting the click to button "sN", whose
                "*type-sN" attributes were set out of combat by Ring_Actions. An Action Bar 1
                button ("*pagedbutton-sN") first gets its slot on the bar's current page, from
                the action bar kind's page state driver (frame ref "actionbarpage").

    Live rings: the in-game ring works on a "live" copy of each ring, built out of combat by
    Ring_Live (hidden actions left out, spread submenus opened out). Indices in the secure
    attributes and callbacks are live indices; each live entry remembers where it came from (for
    scroll positions), and Last Used is saved by slice identity.

    Nested rings that scroll (a slice of kind "ring", not expanded): the parent button also carries the child's
    slices as "*type-sN_C". While the ring is held, the mouse wheel is bound to the helper button,
    which steps "ring-scroll-N" for the slice under the cursor. Release fires "sN_<current>".

    Escape while held dismisses the ring, and so does right click (Right-Click to Cancel setting,
    "ring-rightclick"): the helper closes it (OPEN_RING cleared), so the key's release fires nothing.

    Special actions: picking a Close slot ("*close-sN") is a cancel; picking a Last Used slot
    ("*lastused-sN") fires the slot in "ring-last" instead, the menu's last real pick (set out of
    combat from the saved Last Used, kept current by every release; nothing before any); picking
    a First Action ("*first-sN") fires the slot in "ring-first", the first wedge that fires
    something (set at every rebuild; nothing when there's none).

    Mark Target Markers On = Cursor: a tap (the mouse is still on the unit) fires a target
    marker slot's copy ("<suffix>M", TAP_SUFFIX) that marks the mouseover as it fires, also
    through Last Used and First Action. For picks on the wheel, when a menu opens out of combat
    its target marker slots' /tm ("*macrotext-<suffix>") is pointed at the unit under the mouse (a
    token that still names it once the mouse moves: Ring_Kinds.GetUnitUnderMouse), like a ping;
    set back just after the release and when combat starts, so in combat they mark your target.

    Cursor + Focus: the same, and a menu of only target markers ("ring-stealfocus": Close, Last
    Used, First Action and submenus of markers allowed, since any other action couldn't clear the
    focus) steals your focus when the press finds a unit under the mouse that wasn't aimed at
    (in combat, or no nameplate): the press's click fires on its key down ("useOnKeyDown") as
    "FocusSteal" (/focus [@mouseover]), and FOCUS_STOLEN makes the pick fire the marker's copy
    that marks the focus and clears it ("<suffix>F"); a cancel, dismiss or Close fires "FocusClear"
    (/clearfocus) instead of nothing.

    Menu Style = Relaxed ("ring-relaxed"): the key's release fires nothing and leaves the ring open
    (RELAXED_OPEN) with its bindings, and the probe still up. There's no quick action on a tap:
    secure code can't time the press in combat, so it couldn't tell a tap from a still hold. Left
    click is bound to the ring button itself as "RelaxedSelect", which picks on the click's up by
    the same rules as a Quick release (slice, quick action while the cursor never left the probe,
    else nothing). Escape (and right click, with Right-Click to Cancel) dismisses it through the
    helper, and the keybind's next key down closes it.

    These bindings (plain, and with the ring keybind's modifiers, "ring-keymods": a
    CTRL-SPACE ring keeps CTRL held) are owned by the helper button and cleared on every ring key
    down, close and dismiss. All snippets share the controller's restricted environment
    (OPEN_RING, OPEN_BUTTON, RELAXED_OPEN, START_X/Y).

    Rebuilds (after "Ring.DataChanged" and settings changes) happen out of combat, and never while
    a menu is held open: the attributes the release is about to use must match what's shown.
]]

local env = select(2, ...)
local Config = env.Config
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local SavedVariables = env.AX_Modules:Import("ax_modules\\saved-variables")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Live = env.AX_Modules:Import("@\\Ring\\Live")
local Ring_Display = env.AX_Modules:Import("@\\Ring\\Display")
local Ring_View = env.AX_Modules:Import("@\\Ring\\View")
local Ring_Secure = env.AX_Modules:New("@\\Ring\\Secure")

local InCombatLockdown = InCombatLockdown

local PRE_CLICK = [[
    local screen = owner:GetFrameRef("screen")
    local probe = owner:GetFrameRef("probe")
    local helper = owner:GetFrameRef("helper")
    local ringId = self:GetAttribute("ring-id")
    local relaxed = self:GetAttribute("ring-relaxed")
    -- Relaxed: a left click on the open menu ("RelaxedSelect", bound below) picks, on its release.
    local isPick = button == "RelaxedSelect"
    if isPick and down then return false end
    -- Clicks fire on release, except the key down that steals focus (below).
    self:SetAttribute("useOnKeyDown", false)

    if down then
        -- Relaxed: the keybind again closes the open menu, firing nothing (clearing a stolen focus:
        -- this click fires on its key down).
        if RELAXED_OPEN == ringId and OPEN_RING == ringId then
            OPEN_RING = nil
            OPEN_BUTTON = nil
            RELAXED_OPEN = nil
            helper:ClearBindings()
            probe:UnregisterAutoHide()
            probe:Hide()
            owner:CallMethod("OnRingClose", ringId, "cancel", nil)
            if FOCUS_STOLEN then
                FOCUS_STOLEN = nil
                self:SetAttribute("useOnKeyDown", true)
                return "FocusClear"
            end
            return false
        end

        -- A ring opens with slices on its wheel, or with only a (tap-only) quick action.
        if (self:GetAttribute("ring-count") or 0) == 0 and not self:GetAttribute("ring-quick") then return false end
        local x, y = screen:GetMousePosition()
        if not x then return false end

        helper:ClearBindings()
        START_X, START_Y = x * screen:GetWidth(), y * screen:GetHeight()
        OPEN_RING = ringId
        OPEN_BUTTON = self
        RELAXED_OPEN = nil
        FOCUS_STOLEN = nil

        local probeSize = self:GetAttribute("ring-probe")
        probe:ClearAllPoints()
        probe:SetWidth(probeSize)
        probe:SetHeight(probeSize)
        probe:SetPoint("CENTER", screen, "BOTTOMLEFT", START_X, START_Y)
        probe:Show()
        probe:RegisterAutoHide(0)

        -- While open: Escape (and right click, with Right-Click to Cancel) dismisses the ring,
        -- and the mouse wheel scrolls its scroll slices. Relaxed: also left click picks. A keybind
        -- with modifiers (CTRL-SPACE) may keep them held, and the keys then arrive as CTRL-ESCAPE /
        -- CTRL-BUTTON2 / CTRL-MOUSEWHEELUP: bind those too.
        local keyMods = self:GetAttribute("ring-keymods")
        helper:SetBindingClick(true, "ESCAPE", helper, "Dismiss")
        if keyMods then helper:SetBindingClick(true, keyMods .. "ESCAPE", helper, "Dismiss") end
        if self:GetAttribute("ring-rightclick") then -- Right-Click to Cancel setting
            helper:SetBindingClick(true, "BUTTON2", helper, "Dismiss")
            if keyMods then helper:SetBindingClick(true, keyMods .. "BUTTON2", helper, "Dismiss") end
        end
        if relaxed then
            helper:SetBindingClick(true, "BUTTON1", self, "RelaxedSelect")
            if keyMods then helper:SetBindingClick(true, keyMods .. "BUTTON1", self, "RelaxedSelect") end
        end
        if self:GetAttribute("ring-hasscroll") then
            helper:SetBindingClick(true, "MOUSEWHEELUP", helper, "WheelUp")
            helper:SetBindingClick(true, "MOUSEWHEELDOWN", helper, "WheelDown")
            if keyMods then
                helper:SetBindingClick(true, keyMods .. "MOUSEWHEELUP", helper, "WheelUp")
                helper:SetBindingClick(true, keyMods .. "MOUSEWHEELDOWN", helper, "WheelDown")
            end
        end

        owner:CallMethod("OnRingOpen", ringId, START_X, START_Y)
        -- Cursor + Focus, in a menu of only target markers: the unit under the mouse becomes your
        -- focus, which the markers mark ("<suffix>F"); every way out clears it. This click fires on
        -- its key down. Not when OnRingOpen already aimed the markers at the unit (out of combat, a
        -- unit with a lasting token: "ring-aimed").
        if self:GetAttribute("ring-stealfocus") and not self:GetAttribute("ring-aimed") and UnitExists("mouseover") then
            FOCUS_STOLEN = true
            self:SetAttribute("useOnKeyDown", true)
            return "FocusSteal"
        end
        return false
    end

    -- The keybind's release, or a Relaxed pick.
    if OPEN_RING ~= ringId then return false end

    local moved = not probe:IsShown()
    local result, index
    local x, y = screen:GetMousePosition()
    if x then
        -- Select From = Menu Center: angles from the fixed menu's center, and a release that never
        -- left the quick action square fires the quick action (or nothing), wherever it is.
        local fromMenu = self:GetAttribute("ring-origin") == "menu"
        local originX, originY = START_X, START_Y
        if fromMenu then originX, originY = self:GetAttribute("ring-centerx"), self:GetAttribute("ring-centery") end
        local dx = x * screen:GetWidth() - originX
        local dy = y * screen:GetHeight() - originY
        local deadzone = self:GetAttribute("ring-deadzone")
        local count = self:GetAttribute("ring-count") or 0
        local outside = count > 0 and dx * dx + dy * dy > deadzone * deadzone
        -- A Relaxed pick (click) follows the same rules as a Quick release.
        if fromMenu and not moved then
            index = self:GetAttribute("ring-quick")
            if index then result = "quick" end
        elseif outside then
            local step = 360 / count
            local offset = (90 - math.deg(math.atan2(dy, dx))) % 360
            index = math.floor((offset + step / 2) / step) % count + 1
            result = "slice"
        elseif not moved then
            index = self:GetAttribute("ring-quick")
            if index then result = "quick" end
        end
    end

    -- Relaxed: the release fires nothing. The menu stays open, with its bindings, until a pick or
    -- a dismiss. The probe stays up: leaving it still dismisses the quick action.
    if relaxed and not isPick then
        if RELAXED_OPEN == ringId then return false end
        RELAXED_OPEN = ringId
        owner:CallMethod("OnRingRelaxed", ringId)
        return false
    end

    OPEN_RING = nil
    OPEN_BUTTON = nil
    RELAXED_OPEN = nil
    local stolen = FOCUS_STOLEN
    FOCUS_STOLEN = nil
    helper:ClearBindings()
    probe:UnregisterAutoHide()
    probe:Hide()
    result = result or "cancel"
    -- A Close action: picking it is a cancel, firing nothing (Kinds\Close.lua).
    if index and self:GetAttribute("*close-s" .. index) then index, result = nil, "cancel" end
    -- A First Action: fire the first wedge that fires something instead (Kinds\First.lua).
    if index and self:GetAttribute("*first-s" .. index) then
        index = self:GetAttribute("ring-first")
        if not index then result = "cancel" end
    end
    -- A Last Used action: fire what this menu fired last instead (nothing before anything was),
    -- so that action, not this one, stays the last used (Kinds\LastUsed.lua).
    if index and self:GetAttribute("*lastused-s" .. index) then
        index = self:GetAttribute("ring-last")
        if not index then result = "cancel" end
    end
    if type(index) == "number" then self:SetAttribute("ring-last", index) end

    owner:CallMethod("OnRingClose", ringId, result, index)
    -- Nothing picked: clear a stolen focus.
    if not index then return stolen and "FocusClear" or false end
    local suffix = "s" .. index
    if self:GetAttribute("ring-scrollcount-" .. index) then
        suffix = suffix .. "_" .. (self:GetAttribute("ring-scroll-" .. index) or 1)
    end
    -- Focus stolen: a target marker's copy that marks your focus, then clears it. Else a tap (the
    -- mouse never left the unit): its copy that marks the mouseover (Cursor; also through Last Used
    -- and First Action).
    if stolen and self:GetAttribute("*macrotext-" .. suffix .. "F") then
        suffix = suffix .. "F"
    elseif result == "quick" and self:GetAttribute("*macrotext-" .. suffix .. "M") then
        suffix = suffix .. "M"
    end
    -- An Action Bar 1 button: fire its slot on the bar's page right now (Kinds\ActionBar.lua).
    local pagedButton = self:GetAttribute("*pagedbutton-" .. suffix)
    local pager = pagedButton and owner:GetFrameRef("actionbarpage")
    if pager then
        local page = tonumber(pager:GetAttribute("state-page")) or 1
        self:SetAttribute("*action-" .. suffix, (page - 1) * 12 + pagedButton)
    end
    return suffix
]]

-- Helper button: target of the temporary bindings while a ring is open (Escape and right click
-- dismiss it; the wheel scrolls).
local HELPER_CLICK = [[
    local ring = OPEN_BUTTON
    if not ring then return false end

    -- Right click / Escape: close the ring now, firing nothing. The key's release then finds no
    -- open ring (PRE_CLICK) and does nothing either.
    if button == "Dismiss" then
        local ringId = ring:GetAttribute("ring-id")
        OPEN_RING = nil
        OPEN_BUTTON = nil
        RELAXED_OPEN = nil
        self:ClearBindings()
        local probe = owner:GetFrameRef("probe")
        probe:UnregisterAutoHide()
        probe:Hide()
        owner:CallMethod("OnRingClose", ringId, "cancel", nil)
        -- Clear a stolen focus (Cursor + Focus).
        if FOCUS_STOLEN then
            FOCUS_STOLEN = nil
            return "FocusClear"
        end
        return false
    end

    local screen = owner:GetFrameRef("screen")
    local x, y = screen:GetMousePosition()
    if not x then return false end

    local originX, originY = START_X, START_Y
    if ring:GetAttribute("ring-origin") == "menu" then
        originX, originY = ring:GetAttribute("ring-centerx"), ring:GetAttribute("ring-centery")
    end
    local dx = x * screen:GetWidth() - originX
    local dy = y * screen:GetHeight() - originY
    local deadzone = ring:GetAttribute("ring-deadzone")
    if dx * dx + dy * dy <= deadzone * deadzone then return false end

    local count = ring:GetAttribute("ring-count")
    local step = 360 / count
    local offset = (90 - math.deg(math.atan2(dy, dx))) % 360
    local index = math.floor((offset + step / 2) / step) % count + 1

    local childCount = ring:GetAttribute("ring-scrollcount-" .. index)
    if not childCount or childCount == 0 then return false end

    local current = ring:GetAttribute("ring-scroll-" .. index) or 1
    if button == "WheelUp" then
        current = (current - 2) % childCount + 1
    else
        current = current % childCount + 1
    end
    ring:SetAttribute("ring-scroll-" .. index, current)
    owner:CallMethod("OnRingScroll", ring:GetAttribute("ring-id"), index, current)
    return false
]]

local Controller = CreateFrame("Frame", "RLRM_Controller", UIParent, "SecureHandlerBaseTemplate")

local Screen = CreateFrame("Frame", "RLRM_Screen", UIParent, "SecureFrameTemplate")
Screen:SetAllPoints(UIParent)

local Probe = CreateFrame("Frame", "RLRM_CenterProbe", UIParent, "SecureFrameTemplate")
Probe:SetSize(4, 4)
Probe:Hide()

-- Cursor + Focus: the clicks that steal and clear your focus (on ring buttons, the helper
-- too for FocusClear; the snippets spell the names out), and their macros.
local FOCUS_STEAL, FOCUS_STEAL_TEXT = "FocusSteal", "/focus [@mouseover]"
local FOCUS_CLEAR, FOCUS_CLEAR_TEXT = "FocusClear", "/clearfocus"

local Helper = CreateFrame("Button", "RLRM_RingHelper", UIParent, "SecureActionButtonTemplate")
Helper:SetSize(1, 1)
Helper:EnableMouse(false)
Helper:RegisterForClicks("AnyDown")
-- Its bindings click on key down: fire then (a dismiss clearing a stolen focus).
Helper:SetAttribute("useOnKeyDown", true)
Helper:SetAttribute("*type-" .. FOCUS_CLEAR, "macro")
Helper:SetAttribute("*macrotext-" .. FOCUS_CLEAR, FOCUS_CLEAR_TEXT)
SecureHandlerWrapScript(Helper, "OnClick", Controller, HELPER_CLICK)

-- Clears every target marker, for a Clear target marker that also clears a stolen focus: a
-- macro can't clear them all, so its copy clicks this, then clears the focus.
local ClearMarkers = CreateFrame("Button", "RLRM_ClearMarkers", UIParent, "SecureActionButtonTemplate")
ClearMarkers:SetSize(1, 1)
ClearMarkers:EnableMouse(false)
ClearMarkers:RegisterForClicks("AnyUp") -- /click sends a release
ClearMarkers:SetAttribute("useOnKeyDown", false)
ClearMarkers:SetAttribute("type", "raidtarget")
ClearMarkers:SetAttribute("action", "clear-all")

local ringsById = {}
local pendingBindings = {} -- filled by SetupRing, bound by Rebuild (account keybinds first)
local buttonsById = {}

-- The menu held open right now (between OnRingOpen and OnRingClose), and since when. Rebuilds
-- wait until it's released. A Relaxed menu left open (OnRingRelaxed) waits for its click or
-- dismiss however long that takes: a rebuild would clear its bindings.
local openRingId, openSince, openRelaxed
local MAX_OPEN_TIME = 30 -- s; a held menu "open" longer than this missed its release: don't wait for it

local QueueRebuild -- defined with the rebuild queue below

-- Button suffix of the tap-only quick action ("*type-sQ" ...), and its "ring-quick" value.
local QUICK_SUFFIX = "Q"
local TAP_SUFFIX = "M" -- a target marker's tap copy ("<suffix>M"; PRE_CLICK spells it out)
local FOCUS_SUFFIX = "F" -- a target marker's stolen focus copy ("<suffix>F"; PRE_CLICK spells it out)

--- Mark Target Markers On: the unit under the mouse (Cursor or Cursor + Focus), and whether menus
--- of only target markers steal your focus for it (Cursor + Focus).
local function GetMarkerMode()
    local value = Config.DBGlobal:GetVariable("TargetMarkerUnit")
    local steal = value == env.Enum.TargetMarkerUnit.CursorFocus
    return steal or value == env.Enum.TargetMarkerUnit.Cursor, steal
end

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

--- The action live slice `index` shows: a scroll submenu shows its current action.
local function GetLiveShownSlice(live, index, scrollIndex)
    local slice = live.slices[index]
    return slice and Ring_Live.GetShownSlice(slice, scrollIndex)
end

--- What a Last Used or First Action would fire now (`slice` itself when there's nothing to fire,
--- or for any other action): it shows that action, on a wedge or in the center.
local REDIRECT_ATTRIBUTE = { lastused = "ring-last", first = "ring-first" }
local function ShowRedirect(live, button, slice)
    local attribute = slice and REDIRECT_ATTRIBUTE[slice.kind]
    local target = attribute and button:GetAttribute(attribute)
    if not target then return slice end
    return GetLiveShownSlice(live, target, button:GetAttribute("ring-scroll-" .. target)) or slice
end

-- Target markers on the unit under the mouse when the menu opened: the button and live ring whose
-- marker slots point at it (nil while none do).
local aimedButton, aimedLive

--- Points live ring `live`'s target marker slots at `unit` (nil: your target). Out of combat.
local function AimMarkers(button, live, unit)
    for _, marker in ipairs(live.markerSuffixes) do
        button:SetAttribute("*macrotext-" .. marker.suffix, Ring_Kinds.GetTargetMarkerText(marker.id, unit))
    end
end

local function ResetAimedMarkers()
    if not aimedButton or InCombatLockdown() then return end
    AimMarkers(aimedButton, aimedLive, nil)
    aimedButton:SetAttribute("ring-aimed", nil)
    aimedButton, aimedLive = nil, nil
end

-- Combat starting: markers go back to your target while slots can still be changed.
local aimWatcher = CreateFrame("Frame")
aimWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
aimWatcher:SetScript("OnEvent", ResetAimedMarkers)

--- What each wedge shows, at the scroll positions the button holds.
local function GetDisplaySlices(live, button)
    local slices = {}
    for index = 1, #live.slices do
        local shown = GetLiveShownSlice(live, index, button:GetAttribute("ring-scroll-" .. index))
        slices[index] = ShowRedirect(live, button, shown)
    end
    return slices
end

-- Called from the PRE_CLICK / HELPER_CLICK snippets (owner:CallMethod): insecure display and
-- bookkeeping for the secure flow. Positions are UIParent units.

function Controller:OnRingOpen(ringId, startX, startY)
    local ring = ringsById[ringId]
    if not ring then return end

    openRingId, openSince, openRelaxed = ringId, GetTime(), false
    local button = buttonsById[ringId]
    -- Mark Target Markers On = Cursor: the unit hovered now, like a ping. "ring-aimed" tells
    -- the press snippet, which runs on after this, that it needn't steal your focus.
    if #ring.markerSuffixes > 0 and not InCombatLockdown() and GetMarkerMode() then
        local unit = Ring_Kinds.GetUnitUnderMouse()
        if unit then
            AimMarkers(button, ring, unit)
            button:SetAttribute("ring-aimed", true)
            aimedButton, aimedLive = button, ring
        end
    end
    local displaySlices = GetDisplaySlices(ring, button)
    local quickIndex = button:GetAttribute("ring-quick")
    local quickSlice = quickIndex == QUICK_SUFFIX and ShowRedirect(ring, button, ring.quickSlice)
        or (quickIndex and displaySlices[quickIndex])
    Ring_View:Open(ring, startX, startY, Probe, quickSlice, displaySlices, button:GetAttribute("ring-relaxed") and true or false)
end

--- The mouse wheel moved scroll slice `index` to its child `current`: remember it, update the wedge.
function Controller:OnRingScroll(ringId, index, current)
    local live = ringsById[ringId]
    if not live then return end

    local entry = live.entries[index]
    Ring_Data.SetScrollIndex(entry.ownerId, entry.ownerIndex, current)
    local shown = GetLiveShownSlice(live, index, current)
    Ring_View:SetSliceIcon(index, shown)
    -- The quick action is this scroll slice: a tap fires the child shown, so the center follows.
    local button = buttonsById[ringId]
    if button:GetAttribute("ring-quick") == index then Ring_View:SetQuickSlice(shown) end
    -- This is the first wedge: First Actions fire (and show) the child shown now, on a wedge or
    -- in the center.
    if button:GetAttribute("ring-first") == index then
        for other, slice in ipairs(live.slices) do
            if slice.kind == "first" then Ring_View:SetSliceIcon(other, shown) end
        end
        if live.quickSlice and live.quickSlice.kind == "first" then Ring_View:SetQuickSlice(shown) end
    end
end

--- Relaxed: the keybind was released and the menu stays open until a click or dismiss.
function Controller:OnRingRelaxed(ringId)
    if openRingId ~= ringId then return end
    openRelaxed = true
end

--- @param result string "slice" | "quick" | "cancel"
--- @param index number|string|nil live index, or QUICK_SUFFIX for the tap-only quick action
function Controller:OnRingClose(ringId, result, index)
    Ring_View:Close()
    openRingId, openRelaxed = nil, false
    -- The pick fires after this returns: clear the aimed markers just after it.
    if aimedButton then C_Timer.After(0, ResetAimedMarkers) end

    local live = ringsById[ringId]
    local button = buttonsById[ringId]
    -- Remembered for every menu, for Last Used actions (on a wedge or in the center).
    local slice = live and index and live.slices[index]
    if slice then Ring_Data.SetLastUsedKey(ringId, live.entries[index].key) end

    if env.DEBUG_MODE and index then
        -- What fired, and the attributes the click used (same suffix as the PRE_CLICK snippet).
        local scroll = type(index) == "number" and button:GetAttribute("ring-scrollcount-" .. index)
            and button:GetAttribute("ring-scroll-" .. index)
        local suffix = "s" .. index .. (scroll and ("_" .. scroll) or "")
        local fired = index == QUICK_SUFFIX and live and live.quickSlice or (live and GetLiveShownSlice(live, index, scroll))
        env.Debug(format("%s -> %s: %s | type=%s spell=%s item=%s macro=%s macrotext=%s action=%s marker=%s",
            result, suffix, fired and Ring_Actions.GetLabel(fired) or "?",
            tostring(button:GetAttribute("*type-" .. suffix)), tostring(button:GetAttribute("*spell-" .. suffix)),
            tostring(button:GetAttribute("*item-" .. suffix)), tostring(button:GetAttribute("*macro-" .. suffix)),
            tostring(button:GetAttribute("*macrotext-" .. suffix)), tostring(button:GetAttribute("*action-" .. suffix)),
            tostring(button:GetAttribute("*marker-" .. suffix))))
    else
        env.Debug(result)
    end

    -- A rebuild asked for while the menu was open. Next frame: this runs inside the release's
    -- snippet, before the chosen button is clicked.
    C_Timer.After(0, QueueRebuild)
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
        SecureHandlerWrapScript(button, "OnClick", Controller, PRE_CLICK)
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
    if steal and slice.kind == "targetmarker" then
        focusText = (isMarker and Ring_Kinds.GetTargetMarkerText(slice.id, "focus") or "/click " .. ClearMarkers:GetName())
            .. "\n" .. FOCUS_CLEAR_TEXT
    elseif steal and slice.kind == "close" then
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
    -- Rebuilt: its /tm lines are fresh, so a pending reset (ResetAimedMarkers) has nothing to undo,
    -- and its old slot list may not match the new slots.
    if aimedButton == button then aimedButton, aimedLive = nil, nil end

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
    button:SetAttribute("ring-rightclick", Config.DBGlobal:GetVariable("RightClickDismiss") and true or nil)
    button:SetAttribute("ring-relaxed", Config.DBGlobal:GetVariable("MenuStyle") == env.Enum.MenuStyle.Relaxed or nil)
    if binding and (count > 0 or live.quickSlice) then
        pendingBindings[#pendingBindings + 1] = { key = binding, button = button:GetName(), scope = scope }
    end
end



-- Rebuild: out of combat, with the menu data ready, and not while a menu is held open. Changes
-- made meanwhile are queued and applied as soon as all three hold.

local rebuildQueued = false
local nextFramePending = false -- RequestRebuild's next-frame check is scheduled
local frameRefsSet = false
local combatWaiter = CreateFrame("Frame")

--- Must be called out of combat.
local function Rebuild()
    rebuildQueued = false
    if not frameRefsSet then
        SecureHandlerSetFrameRef(Controller, "screen", Screen)
        SecureHandlerSetFrameRef(Controller, "probe", Probe)
        SecureHandlerSetFrameRef(Controller, "helper", Helper)
        if Ring_Kinds.ActionBarPageFrame then
            SecureHandlerSetFrameRef(Controller, "actionbarpage", Ring_Kinds.ActionBarPageFrame)
        end
        frameRefsSet = true
    end
    ClearOverrideBindings(Controller)
    ClearOverrideBindings(Helper)

    -- Rings that were deleted, or lost their keybind, keep their button (frames can't be
    -- destroyed) but become inert.
    for ringId, button in pairs(buttonsById) do
        button:SetAttribute("ring-count", 0)
        button:SetAttribute("ring-quick", nil)
        ringsById[ringId] = nil
    end

    -- Only keybound rings get a button: a ring is opened by its key, and its submenus' actions are
    -- set on its own button (Ring_Live), so submenus need none of their own.
    wipe(pendingBindings)
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if Ring_Data.GetBinding(ring.id) then SetupRing(ring) end
    end
    -- Widest scope first: where a class or character menu uses the same key, it replaces it here.
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        for _, binding in ipairs(pendingBindings) do
            if binding.scope == scope then
                SetOverrideBindingClick(Controller, true, binding.key, binding.button, "LeftButton")
            end
        end
    end
    CallbackRegistry.Trigger("Ring.Rebuilt")
end

--- Runs a queued rebuild if it can run now; otherwise it runs when combat ends (combatWaiter) or
--- the open menu is released (OnRingClose).
QueueRebuild = function()
    if not rebuildQueued or not Ring_Data.IsReady() then return end
    if InCombatLockdown() then
        combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if openRingId and (openRelaxed or GetTime() - openSince < MAX_OPEN_TIME) then return end
    Rebuild()
end

--- Asks for a rebuild next frame, so several changes at once (built-in menus refilled together, a
--- settings reset) cause one.
--- @param reason string|nil "auto" for automatic updates (quest items, zone ability): no message
local function RequestRebuild(_, reason)
    if not rebuildQueued and reason ~= "auto" and InCombatLockdown() and Ring_Data.IsReady() then
        env.Print("menu changes will apply after combat")
    end
    rebuildQueued = true
    if nextFramePending then return end
    nextFramePending = true
    C_Timer.After(0, function()
        nextFramePending = false
        QueueRebuild()
    end)
end

combatWaiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    QueueRebuild()
end)

CallbackRegistry.Add("Ring.DataReady", function() RequestRebuild(nil, "auto") end)
CallbackRegistry.Add("Ring.DataChanged", RequestRebuild)
-- Dead zone and center nudge live in secure attributes; reveal delay is read by the view on open.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "Deadzone", RequestRebuild)
SavedVariables.OnChange("RL_RadialMenuDB_Global", "ProbeSize", RequestRebuild)
-- World marker actions' macro depends on Place World Markers.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "WorldMarkerPlacement", RequestRebuild)
-- Target markers' tap copies depend on Mark Target Markers On.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "TargetMarkerUnit", RequestRebuild)
-- Right-Click to Cancel decides whether held menus bind right click.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "RightClickDismiss", RequestRebuild)
-- Menu Style decides what the release and the mouse do.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "MenuStyle", RequestRebuild)
CallbackRegistry.Add("Config.Reset", RequestRebuild)
-- Open At, Select From = Menu Center, and the fixed menu's center live in secure attributes too.
CallbackRegistry.Add("Ring.DisplayMoved", function() RequestRebuild(nil, "auto") end)
