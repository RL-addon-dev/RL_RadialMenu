--[[
    Secure ring controller (works in combat). Ring_Secure, one module over the files in this
    folder (Secure.xml), sharing state through "@\\Ring\\Secure\\Private":
        Snippets.lua    this file: how the secure flow works, and its snippets
        Frames.lua      the secure frames, and the names and tables the files share
        Setup.lua       a menu's button and the attributes the snippets read (SetupRing)
        Callbacks.lua   what the snippets call back (OnRingOpen ...): the view, markers, stick keys
        Keys.lua        binding the menus' keys, and taking them back
        Rebuild.lua     rebuilding, out of combat and not while a menu is held open

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

    Controller (WoW Forever's gamepad UI only): a controller's open (GAMEPAD_OPEN): a keybind on
    a controller button (sends "PadKey": GetBindingClick; follows the Menu Style) or a macro (/click RLRM_Ring_<id> Gamepad 1, then
    without the 1 for the release; works like Relaxed whatever the Menu Style). While it's up the
    helper binds B (PAD2) and R3 (PADRSTICK) to close, D-pad up / down to scroll the aimed
    wedge's scroll submenu, the right stick's directions (as keys: SetStickKeys) to the menu's
    button ("Aim"), which keep the pick it leaves ("ring-sticky", which Ring_View shows), and A
    (PAD1) to pick: the stick's direction, else the sticky pick, else the quick action, else
    close. A Quick release picks the same way; in Relaxed, the keybind again closes the menu, like
    B. Flick to Select: letting go of the stick fires its pick, in either menu style. A pick
    with the right stick tilted at least halfway (GetGamePadState's stick 2) takes the stick's
    direction, over the cursor.
    The left stick's directions are never bound, so walking is untouched; Ring_Stick keeps the
    right stick from turning the camera. A button that is the menu's own key ("ring-keybase") is
    left to it.
]]

local env = select(2, ...)
env.AX_Modules:New("@\\Ring\\Secure")
local Private = env.AX_Modules:New("@\\Ring\\Secure\\Private")

local PRE_CLICK = [[
    local screen = owner:GetFrameRef("screen")
    local probe = owner:GetFrameRef("probe")
    local helper = owner:GetFrameRef("helper")
    local ringId = self:GetAttribute("ring-id")
    -- Relaxed: the Menu Style setting, or a controller macro's click ("Gamepad": a macro can't hold
    -- the key, so that open always works like Relaxed). A controller keybind's ("PadKey") follows
    -- the setting.
    local relaxed = self:GetAttribute("ring-relaxed") or button == "Gamepad"
    -- Relaxed: a left click on the open menu ("RelaxedSelect", bound below) picks, on its release.
    local isPick = button == "RelaxedSelect"
    if isPick and down then return false end
    -- A controller's A ("PadUse", bound below) acts on its press only, on the open menu.
    local isPadUse = button == "PadUse"
    -- A controller's open (GAMEPAD_OPEN): the right stick's direction keys ("Aim", bound below: it
    -- left the middle on the press, springs back on the release, straight through where it aimed,
    -- so a small tilt still counts) keep the pick it leaves ("ring-sticky"; A or a Quick release
    -- uses it; Ring_View shows it). A menu whose own key is D-pad up / down gets them bound to
    -- scroll only while the pick is a scroll wedge. Flick to Select ("ring-flick"): a direction
    -- key's release with the stick back under halfway (let go, not turned to another direction)
    -- fires the pick, on that release, in either menu style.
    local isFlick = false
    if button == "Aim" then
        if OPEN_RING ~= ringId then return false end
        local count = self:GetAttribute("ring-count") or 0
        local state = GetGamePadState()
        local stick = state and state.sticks and state.sticks[2]
        if count < 1 or not stick then return false end
        if stick.len >= 0.15 then
            local step = 360 / count
            local offset = (90 - math.deg(math.atan2(stick.y, stick.x))) % 360
            local pick = math.floor((offset + step / 2) / step) % count + 1
            self:SetAttribute("ring-sticky", pick)
            local keyBase = self:GetAttribute("ring-keybase")
            if keyBase == "PADDUP" or keyBase == "PADDDOWN" then
                local scrolls = self:GetAttribute("ring-scrollcount-" .. pick)
                local keyMods = self:GetAttribute("ring-keymods")
                local prefix = ""
                for pass = 1, keyMods and 2 or 1 do
                    if scrolls then
                        helper:SetBindingClick(true, prefix .. "PADDUP", helper, "PadUp")
                        helper:SetBindingClick(true, prefix .. "PADDDOWN", helper, "PadDown")
                    else
                        helper:ClearBinding(prefix .. "PADDUP")
                        helper:ClearBinding(prefix .. "PADDDOWN")
                    end
                    prefix = keyMods
                end
            end
        end
        if down or not GAMEPAD_OPEN or not self:GetAttribute("ring-flick") then return false end
        if stick.len >= 0.5 or not self:GetAttribute("ring-sticky") then return false end
        isFlick = true
    end
    if isPadUse and (not down or OPEN_RING ~= ringId) then return false end
    -- Clicks fire on release, except the key down that steals focus, and a stick pick (below).
    self:SetAttribute("useOnKeyDown", false)

    -- A controller's open: its right stick (GetGamePadState's stick 2), tilted at least halfway,
    -- picks by its direction, over the cursor (Ring_View's highlight follows it the same way).
    local count = self:GetAttribute("ring-count") or 0
    local stickIndex
    if count > 0 and GAMEPAD_OPEN then
        local state = GetGamePadState()
        local stick = state and state.sticks and state.sticks[2]
        if stick and stick.len >= 0.5 then
            local step = 360 / count
            local offset = (90 - math.deg(math.atan2(stick.y, stick.x))) % 360
            stickIndex = math.floor((offset + step / 2) / step) % count + 1
        end
    end
    -- Relaxed: the keybind again with the stick tilted picks that wedge, on its key down; untilted,
    -- it closes the menu. After a controller's open (GAMEPAD_OPEN) it always closes the menu (A
    -- picks, B closes too). A controller's A picks on its key down, in both menu styles.
    local relaxedOpen = RELAXED_OPEN == ringId and OPEN_RING == ringId
    local quickIndex = self:GetAttribute("ring-quick")
    -- A controller's pick (A, or a Quick release): the stick if tilted now, else the pick it left
    -- ("ring-sticky"), else the quick action.
    local sticky = GAMEPAD_OPEN and not stickIndex and self:GetAttribute("ring-sticky")
    local padQuick = GAMEPAD_OPEN and not stickIndex and not sticky and quickIndex
    local pickOnPress = isPadUse or (relaxedOpen and not GAMEPAD_OPEN)
    if down and pickOnPress and (stickIndex or sticky or padQuick) then
        isPick = true
        self:SetAttribute("useOnKeyDown", true)
    end
    if isFlick then isPick = true end -- fires on this release (useOnKeyDown is off)

    if down and not isPick then
        -- Relaxed: the keybind again closes the open menu, firing nothing (clearing a stolen focus:
        -- this click fires on its key down). A with nothing to pick, too.
        if relaxedOpen or isPadUse then
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
        if count == 0 and not quickIndex then return false end
        local x, y = screen:GetMousePosition()
        if not x then return false end

        helper:ClearBindings()
        START_X, START_Y = x * screen:GetWidth(), y * screen:GetHeight()
        OPEN_RING = ringId
        OPEN_BUTTON = self
        RELAXED_OPEN = nil
        FOCUS_STOLEN = nil
        GAMEPAD_OPEN = button == "Gamepad" or button == "PadKey"

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
        -- A controller's open: B and R3 close it; A uses the pick; the right stick's directions
        -- (keys while the menu is up: SetStickKeys) keep the pick it leaves ("Aim"), in combat too;
        -- D-pad up / down scroll the aimed wedge's scroll submenu. The left stick's directions
        -- aren't bound: walking stays untouched. A button that is the menu's own key is left to it.
        if GAMEPAD_OPEN then
            self:SetAttribute("ring-sticky", nil)
            local keyBase = self:GetAttribute("ring-keybase")
            local scrollPad = self:GetAttribute("ring-hasscroll") and keyBase ~= "PADDUP" and keyBase ~= "PADDDOWN"
            local prefix = ""
            for pass = 1, keyMods and 2 or 1 do
                if keyBase ~= "PAD2" then helper:SetBindingClick(true, prefix .. "PAD2", helper, "Dismiss") end
                if keyBase ~= "PAD1" then helper:SetBindingClick(true, prefix .. "PAD1", self, "PadUse") end
                if keyBase ~= "PADRSTICK" then helper:SetBindingClick(true, prefix .. "PADRSTICK", helper, "Dismiss") end
                helper:SetBindingClick(true, prefix .. "PADRSTICKUP", self, "Aim")
                helper:SetBindingClick(true, prefix .. "PADRSTICKDOWN", self, "Aim")
                helper:SetBindingClick(true, prefix .. "PADRSTICKLEFT", self, "Aim")
                helper:SetBindingClick(true, prefix .. "PADRSTICKRIGHT", self, "Aim")
                if scrollPad then
                    helper:SetBindingClick(true, prefix .. "PADDUP", helper, "PadUp")
                    helper:SetBindingClick(true, prefix .. "PADDDOWN", helper, "PadDown")
                end
                prefix = keyMods
            end
        end
        if self:GetAttribute("ring-hasscroll") then
            helper:SetBindingClick(true, "MOUSEWHEELUP", helper, "WheelUp")
            helper:SetBindingClick(true, "MOUSEWHEELDOWN", helper, "WheelDown")
            if keyMods then
                helper:SetBindingClick(true, keyMods .. "MOUSEWHEELUP", helper, "WheelUp")
                helper:SetBindingClick(true, keyMods .. "MOUSEWHEELDOWN", helper, "WheelDown")
            end
        end

        owner:CallMethod("OnRingOpen", ringId, START_X, START_Y, relaxed and true or false, GAMEPAD_OPEN)
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

    -- The keybind's release, or a Relaxed pick (a click, or the keybind with the stick tilted).
    if OPEN_RING ~= ringId then return false end

    local moved = not probe:IsShown()
    local result, index
    local x, y = screen:GetMousePosition()
    if stickIndex then
        index, result = stickIndex, "slice"
    elseif sticky then -- a controller's pick, stick let go
        index, result = sticky, "slice"
    elseif padQuick then -- a controller's pick, nothing aimed at
        index, result = quickIndex, "quick"
    elseif x then
        -- Select From = Menu Center: angles from the fixed menu's center, and a release that never
        -- left the quick action square fires the quick action (or nothing), wherever it is.
        local fromMenu = self:GetAttribute("ring-origin") == "menu"
        local originX, originY = START_X, START_Y
        if fromMenu then originX, originY = self:GetAttribute("ring-centerx"), self:GetAttribute("ring-centery") end
        local dx = x * screen:GetWidth() - originX
        local dy = y * screen:GetHeight() - originY
        local deadzone = self:GetAttribute("ring-deadzone")
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
    if not down then return false end

    -- A controller's open (GAMEPAD_OPEN): D-pad up / down ("PadUp" / "PadDown") scroll the scroll
    -- submenu of the picked wedge ("ring-sticky", kept by the right stick's "Aim": PRE_CLICK).
    if button == "PadUp" or button == "PadDown" then
        local index = ring:GetAttribute("ring-sticky")
        local childCount = index and ring:GetAttribute("ring-scrollcount-" .. index)
        if not childCount or childCount < 1 then return false end
        local current = ring:GetAttribute("ring-scroll-" .. index) or 1
        if button == "PadUp" then
            current = (current - 2) % childCount + 1
        else
            current = current % childCount + 1
        end
        ring:SetAttribute("ring-scroll-" .. index, current)
        owner:CallMethod("OnRingScroll", ring:GetAttribute("ring-id"), index, current)
        return false
    end

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

Private.PRE_CLICK = PRE_CLICK
Private.HELPER_CLICK = HELPER_CLICK
