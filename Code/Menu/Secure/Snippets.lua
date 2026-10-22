--[[
    Menu_Secure: the secure menu controller, which works in combat. It's one module over the files
    in this folder (Secure.xml), which share state through "@\\Menu\\Secure\\Private".
        Snippets.lua    this file, with how the secure flow works and its snippets
        Frames.lua      the secure frames, and the names and tables the files share
        Setup.lua       a menu's button and the attributes the snippets read (SetupMenu)
        Callbacks.lua   what the snippets call back (OnMenuOpen...), for the view, markers and stick keys
        Keys.lua        binding the menus' keys, and taking them back
        Rebuild.lua     rebuilding, out of combat and not while a menu is held open

    The snippets run in the restricted environment, which can't see Lua constants. So they spell
    out the attribute and click names that Menu_Secure.Attribute and Menu_Secure.Click hold, and a
    rename has to change both. They also can't share functions, so the wedge an angle points at
    (wedges clockwise from the top) is worked out the same way in four places, three in PRE_CLICK
    and one in HELPER_CLICK. Menu_Layout.GetWedgeIndex matches them, so change them all together.

    Each keybound menu is a hidden SecureActionButton, bound with an override binding and
    registered for AnyDown and AnyUp. Its OnClick is wrapped by a restricted snippet (PRE_CLICK).

    On key down, it records where the cursor starts, places the center probe under the cursor and
    opens the view. The probe hides itself (secure auto-hide) as soon as the cursor leaves it. The
    click is cancelled, so nothing fires.

    On key up, it picks from the cursor's offset from the key down spot, or from the fixed menu's
    center with Select From = Menu Center.
        1. Outside the dead zone, the wedge at that angle.
        2. Inside it with the probe still shown (the cursor never left the center), the quick action.
        3. Inside it with the probe hidden, nothing.
    The pick fires by redirecting the click to button "sN", whose "*type-sN" attributes Menu_Actions
    set out of combat. An Action Bar 1 button ("*pagedbutton-sN") first gets its slot on the bar's
    current page, from the action bar kind's page state driver (frame ref "actionbarpage").

    Live menus: the in-game menu works on a live copy of each menu, which Menu_Live builds out of
    combat (hidden actions left out, spread submenus opened out). Indexes in the secure attributes
    and callbacks are live indexes. Each live entry remembers where it came from, for scroll
    positions, and Last Used is saved by action identity.

    Scroll submenus (an action of kind "submenu" that isn't spread out): the parent button also carries
    the child's actions as "*type-sN_C". While the menu is held, the mouse wheel is bound to the
    helper button, which steps "menu-scroll-N" for the wedge under the cursor. The release fires
    "sN_<current>".

    Escape while held dismisses the menu, and so does right click with Right-Click to Cancel
    ("menu-rightclick"). The helper closes it (OPEN_MENU cleared), so the key's release fires
    nothing.

    Special actions:
        - Picking a Close action ("*close-sN") is a cancel.
        - Picking a Last Used action ("*lastused-sN") fires the wedge in "menu-last" instead. That's
          the menu's last real pick, set out of combat from the saved Last Used and kept current by
          every release. Before any pick there's nothing to fire.
        - Picking a First Action ("*first-sN") fires the wedge in "menu-first" instead. That's the
          first wedge that fires something, set at every rebuild, or nothing when there's none.

    Mark Target Markers On = Cursor: a tap (the mouse still on the unit) fires a target marker
    wedge's copy ("<suffix>M", TAP_SUFFIX), which marks the mouseover as it fires. That works
    through Last Used and First Action too. For picks on the wheel, when a menu opens out of combat
    its target markers' /tm ("*macrotext-<suffix>") is pointed at the unit under the mouse, like a
    ping. It uses a token that still names the unit once the mouse moves
    (Utils_Unit.GetUnitUnderMouse). The macros are set back just after the release and when combat
    starts, so in combat they mark your target.

    Cursor + Focus works the same, and a menu of only target markers ("menu-stealfocus") also
    steals your focus. Close, Last Used, First Action and submenus of markers are allowed in it,
    since any other action couldn't clear the focus. When the press finds a unit under the mouse
    that wasn't aimed at (in combat, or without a nameplate), the press's click fires on its key
    down ("useOnKeyDown") as "FocusSteal", a focus action on the mouseover. It isn't a macro,
    because a crossbar macro's open would run it from inside a macro. FOCUS_STOLEN then makes the pick
    fire the marker's copy that marks the focus and clears it ("<suffix>F"). A cancel, dismiss or
    Close fires "FocusClear" (/clearfocus) instead of nothing.

    Menu Style = Relaxed ("menu-relaxed"): the key's release fires nothing and leaves the menu open
    (RELAXED_OPEN, set on the open itself for a controller's), with its bindings and the probe
    still up. There's no quick action on a tap,
    because secure code can't time the press in combat and so couldn't tell a tap from a still
    hold. Left click is bound to the menu button itself as "RelaxedSelect", which picks on the
    click's release by the same rules as a Quick release. Escape (and right click, with Right-Click
    to Cancel) dismisses it through the helper, and the keybind's next key down closes it.

    These bindings are owned by the helper button, and cleared on every menu key down, close and
    dismiss. They're bound plain and with the menu keybind's modifiers ("menu-keymods"), since a
    CTRL-SPACE menu keeps CTRL held. All snippets share the controller's restricted environment
    (OPEN_MENU, OPEN_BUTTON, RELAXED_OPEN, START_X and START_Y).

    Controller (WoW Forever's gamepad UI only): a controller's open (GAMEPAD_OPEN) is a click sent
    as "Gamepad". It comes from a keybind on a controller button (GetBindingClick), a crossbar
    macro or a stick's dispatcher (/click RLRM_<id> Gamepad 1, then without the 1 for the
    release). Menus work like Relaxed in that UI ("menu-relaxed", Setup.lua). While a menu is up,
    the helper binds these.
        - B (PAD2) and R3 (PADRSTICK) close it.
        - D-pad up and down scroll the aimed wedge's scroll submenu.
        - The right stick's directions, as keys (SetStickKeys), click the menu's button as "Aim".
          They keep the pick the stick leaves ("menu-sticky"), which Menu_View shows.
        - A (PAD1) picks the stick's direction, else the sticky pick, else the quick action, else
          closes the menu.
    A Quick release picks the same way. In Relaxed, the keybind again closes the menu, like B. With
    Flick to Select, letting go of the stick fires its pick, in either menu style. A pick with the
    right stick tilted at least halfway (GetGamePadState's stick 2) takes the stick's direction
    over the cursor. The left stick's directions are never bound, so walking is untouched, and
    Menu_Stick keeps the right stick from turning the camera. R3 or a D-pad button that is the
    menu's own key ("menu-keybase") is left to it, but A and B always pick and close (with
    ConsolePort, the menu's key can be A or B). With ConsolePort, those controller keys are
    claimed in its binding layers too (BIND_PAD), since it binds the buttons again whenever a
    modifier changes.
]]

local env = select(2, ...)
env.AX_Modules:New("@\\Menu\\Secure")
local Private = env.AX_Modules:New("@\\Menu\\Secure\\Private")

-- Binds a controller key while a menu is open, and claims it in ConsolePort's layers so it can't
-- take the key back. Run as RunAttribute("BindPad", key, frame name, button).
Private.BIND_PAD = [[
    local key, target, button = ...
    self:GetFrameRef("helper"):SetBindingClick(true, key, target, button)
    self:RunAttribute("consoleport-claim", key, target, button)
]]
-- Unbinds a key BIND_PAD bound, while the menu stays open (RunAttribute "UnbindPad", the key).
Private.UNBIND_PAD = [[
    local key = ...
    self:GetFrameRef("helper"):ClearBinding(key)
    self:RunAttribute("consoleport-release", key)
]]

-- The menu button's OnClick, wrapped by the controller (Setup.lua). It returns the button to
-- redirect the click to ("s3", "s3_2", "FocusSteal"...), or false to fire nothing.
Private.PRE_CLICK = [[
    local screen = owner:GetFrameRef("screen")
    local probe = owner:GetFrameRef("probe")
    local helper = owner:GetFrameRef("helper")
    local menuId = self:GetAttribute("menu-id")
    -- Relaxed is the Menu Style setting (always on in WoW Forever's gamepad UI), or a controller's
    -- click ("Gamepad"), since a macro can't hold the key.
    local relaxed = self:GetAttribute("menu-relaxed") or button == "Gamepad"
    -- In Relaxed, a left click on the open menu ("RelaxedSelect", bound below) picks on its release.
    local isPick = button == "RelaxedSelect"
    if isPick and down then return false end
    -- A controller's A ("PadUse", bound below) acts on its press only, on the open menu.
    local isPadUse = button == "PadUse"
    -- In a controller's open (GAMEPAD_OPEN), the right stick's direction keys ("Aim", bound below)
    -- keep the pick the stick leaves ("menu-sticky"), which A or a Quick release uses and Menu_View
    -- shows. The stick left the middle on the press and springs back on the release, straight
    -- through where it aimed, so a small tilt still counts. A menu whose own key is D-pad up or
    -- down gets them bound to scroll only while the pick is a scroll wedge. With Flick to Select
    -- ("menu-flick"), a direction key's release with the stick back under halfway (let go, not
    -- turned to another direction) fires the pick on that release, in either menu style.
    local isFlick = false
    if button == "Aim" then
        if OPEN_MENU ~= menuId then return false end
        local count = self:GetAttribute("menu-count") or 0
        local state = GetGamePadState()
        local stick = state and state.sticks and state.sticks[2]
        if count < 1 or not stick then return false end
        if stick.len >= 0.15 then
            local step = 360 / count
            local offset = (90 - math.deg(math.atan2(stick.y, stick.x))) % 360
            local pick = math.floor((offset + step / 2) / step) % count + 1
            self:SetAttribute("menu-sticky", pick)
            local keyBase = self:GetAttribute("menu-keybase")
            if keyBase == "PADDUP" or keyBase == "PADDDOWN" then
                local scrolls = self:GetAttribute("menu-scrollcount-" .. pick)
                local keyMods = self:GetAttribute("menu-keymods")
                local prefix, helperName = "", helper:GetName()
                for pass = 1, keyMods and 2 or 1 do
                    if scrolls then
                        owner:RunAttribute("BindPad", prefix .. "PADDUP", helperName, "PadUp")
                        owner:RunAttribute("BindPad", prefix .. "PADDDOWN", helperName, "PadDown")
                    else
                        owner:RunAttribute("UnbindPad", prefix .. "PADDUP")
                        owner:RunAttribute("UnbindPad", prefix .. "PADDDOWN")
                    end
                    prefix = keyMods
                end
            end
        end
        if down or not GAMEPAD_OPEN or not self:GetAttribute("menu-flick") then return false end
        if stick.len >= 0.5 or not self:GetAttribute("menu-sticky") then return false end
        isFlick = true
    end
    if isPadUse and (not down or OPEN_MENU ~= menuId) then return false end
    -- Clicks fire on release, except the key down that steals focus, and a stick pick (below).
    self:SetAttribute("useOnKeyDown", false)

    -- In a controller's open, the right stick (GetGamePadState's stick 2) tilted at least halfway
    -- picks by its direction, over the cursor. Menu_View's highlight follows it the same way.
    local count = self:GetAttribute("menu-count") or 0
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
    -- In Relaxed, the keybind again with the stick tilted picks that wedge on its key down, and
    -- untilted it closes the menu. After a controller's open (GAMEPAD_OPEN) it always closes the
    -- menu, since A picks and B closes too. A controller's A picks on its key down, in both menu
    -- styles.
    local relaxedOpen = RELAXED_OPEN == menuId and OPEN_MENU == menuId
    local quickIndex = self:GetAttribute("menu-quick")
    -- A controller's pick (A, or a Quick release) is the stick if tilted now, else the pick it left
    -- ("menu-sticky"), else the quick action.
    local sticky = GAMEPAD_OPEN and not stickIndex and self:GetAttribute("menu-sticky")
    local padQuick = GAMEPAD_OPEN and not stickIndex and not sticky and quickIndex
    local pickOnPress = isPadUse or (relaxedOpen and not GAMEPAD_OPEN)
    if down and pickOnPress and (stickIndex or sticky or padQuick) then
        isPick = true
        self:SetAttribute("useOnKeyDown", true)
    end
    if isFlick then isPick = true end -- fires on this release (useOnKeyDown is off)

    if down and not isPick then
        -- In Relaxed, the keybind again closes the open menu and fires nothing, except clearing a
        -- stolen focus (this click fires on its key down). So does A with nothing to pick.
        if relaxedOpen or isPadUse then
            OPEN_MENU = nil
            OPEN_BUTTON = nil
            RELAXED_OPEN = nil
            helper:ClearBindings()
            owner:RunAttribute("consoleport-release")
            probe:UnregisterAutoHide()
            probe:Hide()
            owner:CallMethod("OnMenuClose", menuId, "cancel", nil)
            if FOCUS_STOLEN then
                FOCUS_STOLEN = nil
                self:SetAttribute("useOnKeyDown", true)
                return "FocusClear"
            end
            return false
        end

        -- A menu opens with wedges on its wheel, or with only a quick action (tap only).
        if count == 0 and not quickIndex then return false end
        local x, y = screen:GetMousePosition()
        if not x then return false end

        helper:ClearBindings()
        owner:RunAttribute("consoleport-release")
        START_X, START_Y = x * screen:GetWidth(), y * screen:GetHeight()
        OPEN_MENU = menuId
        OPEN_BUTTON = self
        RELAXED_OPEN = nil
        FOCUS_STOLEN = nil
        GAMEPAD_OPEN = button == "Gamepad"

        local probeSize = self:GetAttribute("menu-probe")
        probe:ClearAllPoints()
        probe:SetWidth(probeSize)
        probe:SetHeight(probeSize)
        probe:SetPoint("CENTER", screen, "BOTTOMLEFT", START_X, START_Y)
        probe:Show()
        probe:RegisterAutoHide(0)

        -- While the menu is open, Escape (and right click, with Right-Click to Cancel) dismisses it,
        -- and the mouse wheel scrolls its scroll wedges. In Relaxed, left click also picks. A
        -- keybind with modifiers (CTRL-SPACE) may keep them held, and the keys then arrive as
        -- CTRL-ESCAPE, CTRL-BUTTON2 or CTRL-MOUSEWHEELUP, so those are bound too.
        local keyMods = self:GetAttribute("menu-keymods")
        helper:SetBindingClick(true, "ESCAPE", helper, "Dismiss")
        if keyMods then helper:SetBindingClick(true, keyMods .. "ESCAPE", helper, "Dismiss") end
        if self:GetAttribute("menu-rightclick") then -- Right-Click to Cancel setting
            helper:SetBindingClick(true, "BUTTON2", helper, "Dismiss")
            if keyMods then helper:SetBindingClick(true, keyMods .. "BUTTON2", helper, "Dismiss") end
        end
        if relaxed then
            helper:SetBindingClick(true, "BUTTON1", self, "RelaxedSelect")
            if keyMods then helper:SetBindingClick(true, keyMods .. "BUTTON1", self, "RelaxedSelect") end
        end
        -- In a controller's open, B and R3 close the menu and A uses the pick. The right stick's
        -- directions (keys while the menu is up, see SetStickKeys) keep the pick it leaves ("Aim"),
        -- in combat too. D-pad up and down scroll the aimed wedge's scroll submenu. The left
        -- stick's directions aren't bound, so walking stays untouched. R3 or a D-pad button that is
        -- the menu's own key is left to it. A and B always pick and close, even when the menu's
        -- key is one of them (ConsolePort, where any button can be one), and with or without its
        -- modifiers held. They're bound with BIND_PAD, which ConsolePort can't take back.
        if GAMEPAD_OPEN then
            self:SetAttribute("menu-sticky", nil)
            local keyBase = self:GetAttribute("menu-keybase")
            local scrollPad = self:GetAttribute("menu-hasscroll") and keyBase ~= "PADDUP" and keyBase ~= "PADDDOWN"
            local prefix, helperName, menuName = "", helper:GetName(), self:GetName()
            for pass = 1, keyMods and 2 or 1 do
                owner:RunAttribute("BindPad", prefix .. "PAD2", helperName, "Dismiss")
                owner:RunAttribute("BindPad", prefix .. "PAD1", menuName, "PadUse")
                if keyBase ~= "PADRSTICK" then owner:RunAttribute("BindPad", prefix .. "PADRSTICK", helperName, "Dismiss") end
                owner:RunAttribute("BindPad", prefix .. "PADRSTICKUP", menuName, "Aim")
                owner:RunAttribute("BindPad", prefix .. "PADRSTICKDOWN", menuName, "Aim")
                owner:RunAttribute("BindPad", prefix .. "PADRSTICKLEFT", menuName, "Aim")
                owner:RunAttribute("BindPad", prefix .. "PADRSTICKRIGHT", menuName, "Aim")
                if scrollPad then
                    owner:RunAttribute("BindPad", prefix .. "PADDUP", helperName, "PadUp")
                    owner:RunAttribute("BindPad", prefix .. "PADDDOWN", helperName, "PadDown")
                end
                prefix = keyMods
            end
        end
        if self:GetAttribute("menu-hasscroll") then
            helper:SetBindingClick(true, "MOUSEWHEELUP", helper, "WheelUp")
            helper:SetBindingClick(true, "MOUSEWHEELDOWN", helper, "WheelDown")
            if keyMods then
                helper:SetBindingClick(true, keyMods .. "MOUSEWHEELUP", helper, "WheelUp")
                helper:SetBindingClick(true, keyMods .. "MOUSEWHEELDOWN", helper, "WheelDown")
            end
        end

        owner:CallMethod("OnMenuOpen", menuId, START_X, START_Y, relaxed and true or false, GAMEPAD_OPEN)
        -- A controller's open is always Relaxed, so it counts as left open now, not on the
        -- release. When the menu's own key is A or B, the open just bound it to pick or close, so
        -- its release may not come back here.
        if GAMEPAD_OPEN then
            RELAXED_OPEN = menuId
            owner:CallMethod("OnMenuRelaxed", menuId)
        end
        -- With Cursor + Focus, in a menu of only target markers, the unit under the mouse becomes
        -- your focus, which the markers mark ("<suffix>F"). Every way out clears it. This click
        -- fires on its key down. It's skipped when OnMenuOpen already aimed the markers at the
        -- unit ("menu-aimed"), out of combat with a unit that has a lasting token.
        if self:GetAttribute("menu-stealfocus") and not self:GetAttribute("menu-aimed") and UnitExists("mouseover") then
            FOCUS_STOLEN = true
            self:SetAttribute("useOnKeyDown", true)
            return "FocusSteal"
        end
        return false
    end

    -- The keybind's release, or a Relaxed pick (a click, or the keybind with the stick tilted).
    if OPEN_MENU ~= menuId then return false end

    local moved = not probe:IsShown()
    local result, index
    local x, y = screen:GetMousePosition()
    if stickIndex then
        index, result = stickIndex, "action"
    elseif sticky then -- a controller's pick, stick let go
        index, result = sticky, "action"
    elseif padQuick then -- a controller's pick, nothing aimed at
        index, result = quickIndex, "quick"
    elseif x then
        -- With Select From = Menu Center, angles are from the fixed menu's center, and a release
        -- that never left the quick action square fires the quick action (or nothing), wherever
        -- it is.
        local fromMenu = self:GetAttribute("menu-origin") == "menu"
        local originX, originY = START_X, START_Y
        if fromMenu then originX, originY = self:GetAttribute("menu-centerx"), self:GetAttribute("menu-centery") end
        local dx = x * screen:GetWidth() - originX
        local dy = y * screen:GetHeight() - originY
        local deadzone = self:GetAttribute("menu-deadzone")
        local outside = count > 0 and dx * dx + dy * dy > deadzone * deadzone
        -- A Relaxed pick (click) follows the same rules as a Quick release.
        if fromMenu and not moved then
            index = self:GetAttribute("menu-quick")
            if index then result = "quick" end
        elseif outside then
            local step = 360 / count
            local offset = (90 - math.deg(math.atan2(dy, dx))) % 360
            index = math.floor((offset + step / 2) / step) % count + 1
            result = "action"
        elseif not moved then
            index = self:GetAttribute("menu-quick")
            if index then result = "quick" end
        end
    end

    -- In Relaxed, the release fires nothing. The menu stays open, with its bindings, until a pick
    -- or a dismiss. The probe stays up, so leaving it still dismisses the quick action.
    if relaxed and not isPick then
        if RELAXED_OPEN == menuId then return false end
        RELAXED_OPEN = menuId
        owner:CallMethod("OnMenuRelaxed", menuId)
        return false
    end

    OPEN_MENU = nil
    OPEN_BUTTON = nil
    RELAXED_OPEN = nil
    local stolen = FOCUS_STOLEN
    FOCUS_STOLEN = nil
    helper:ClearBindings()
    owner:RunAttribute("consoleport-release")
    probe:UnregisterAutoHide()
    probe:Hide()
    result = result or "cancel"
    -- Picking a Close action is a cancel, firing nothing (Kinds\Close.lua).
    if index and self:GetAttribute("*close-s" .. index) then index, result = nil, "cancel" end
    -- A First Action fires the first wedge that fires something instead (Kinds\First.lua).
    if index and self:GetAttribute("*first-s" .. index) then
        index = self:GetAttribute("menu-first")
        if not index then result = "cancel" end
    end
    -- A Last Used action fires what this menu fired last instead (nothing before anything was), so
    -- that action, not this one, stays the last used (Kinds\LastUsed.lua).
    if index and self:GetAttribute("*lastused-s" .. index) then
        index = self:GetAttribute("menu-last")
        if not index then result = "cancel" end
    end
    if type(index) == "number" then self:SetAttribute("menu-last", index) end

    owner:CallMethod("OnMenuClose", menuId, result, index)
    -- With nothing picked, a stolen focus is cleared.
    if not index then return stolen and "FocusClear" or false end
    local suffix = "s" .. index
    if self:GetAttribute("menu-scrollcount-" .. index) then
        suffix = suffix .. "_" .. (self:GetAttribute("menu-scroll-" .. index) or 1)
    end
    -- With the focus stolen, a target marker fires its copy that marks your focus and then clears
    -- it. Else a tap (the mouse never left the unit) fires its copy that marks the mouseover
    -- (Cursor), also through Last Used and First Action.
    if stolen and self:GetAttribute("*macrotext-" .. suffix .. "F") then
        suffix = suffix .. "F"
    elseif result == "quick" and self:GetAttribute("*macrotext-" .. suffix .. "M") then
        suffix = suffix .. "M"
    end
    -- An Action Bar 1 button fires its slot on the bar's page right now (Kinds\ActionBar.lua).
    local pagedButton = self:GetAttribute("*pagedbutton-" .. suffix)
    local pager = pagedButton and owner:GetFrameRef("actionbarpage")
    if pager then
        local page = tonumber(pager:GetAttribute("state-page")) or 1
        self:SetAttribute("*action-" .. suffix, (page - 1) * 12 + pagedButton)
    end
    return suffix
]]

-- The helper button's OnClick. The helper is the target of the temporary bindings while a menu is
-- open. Escape and right click dismiss the menu, and the wheel and D-pad scroll it.
Private.HELPER_CLICK = [[
    local menu = OPEN_BUTTON
    if not menu then return false end
    if not down then return false end

    -- In a controller's open (GAMEPAD_OPEN), D-pad up and down ("PadUp", "PadDown") scroll the
    -- scroll submenu of the picked wedge ("menu-sticky", kept by the right stick's "Aim" in
    -- PRE_CLICK).
    if button == "PadUp" or button == "PadDown" then
        local index = menu:GetAttribute("menu-sticky")
        local childCount = index and menu:GetAttribute("menu-scrollcount-" .. index)
        if not childCount or childCount < 1 then return false end
        local current = menu:GetAttribute("menu-scroll-" .. index) or 1
        if button == "PadUp" then
            current = (current - 2) % childCount + 1
        else
            current = current % childCount + 1
        end
        menu:SetAttribute("menu-scroll-" .. index, current)
        owner:CallMethod("OnMenuScroll", menu:GetAttribute("menu-id"), index, current)
        return false
    end

    -- Right click and Escape close the menu now, firing nothing. The key's release then finds no
    -- open menu (PRE_CLICK) and does nothing either.
    if button == "Dismiss" then
        local menuId = menu:GetAttribute("menu-id")
        OPEN_MENU = nil
        OPEN_BUTTON = nil
        RELAXED_OPEN = nil
        self:ClearBindings()
        owner:RunAttribute("consoleport-release")
        local probe = owner:GetFrameRef("probe")
        probe:UnregisterAutoHide()
        probe:Hide()
        owner:CallMethod("OnMenuClose", menuId, "cancel", nil)
        -- A stolen focus is cleared (Cursor + Focus).
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
    if menu:GetAttribute("menu-origin") == "menu" then
        originX, originY = menu:GetAttribute("menu-centerx"), menu:GetAttribute("menu-centery")
    end
    local dx = x * screen:GetWidth() - originX
    local dy = y * screen:GetHeight() - originY
    local deadzone = menu:GetAttribute("menu-deadzone")
    if dx * dx + dy * dy <= deadzone * deadzone then return false end

    local count = menu:GetAttribute("menu-count")
    local step = 360 / count
    local offset = (90 - math.deg(math.atan2(dy, dx))) % 360
    local index = math.floor((offset + step / 2) / step) % count + 1

    local childCount = menu:GetAttribute("menu-scrollcount-" .. index)
    if not childCount or childCount == 0 then return false end

    local current = menu:GetAttribute("menu-scroll-" .. index) or 1
    if button == "WheelUp" then
        current = (current - 2) % childCount + 1
    else
        current = current % childCount + 1
    end
    menu:SetAttribute("menu-scroll-" .. index, current)
    owner:CallMethod("OnMenuScroll", menu:GetAttribute("menu-id"), index, current)
    return false
]]

-- A stick dispatcher's OnClick (WoW Forever's gamepad UI only). L3 or R3 is bound to its
-- dispatcher once a menu uses that stick (Menu_Crossbar, Keys.lua). Its key down reads which
-- crossbar modifiers are held (GetGamePadState, by the button indexes in "modifier-LEFT" and
-- "modifier-RIGHT"). It then opens that side's menu like a crossbar macro, with a press and a
-- release, since menus work like Relaxed in that UI. The menus are "side-TOP" for the plain stick,
-- then "side-LEFT", "side-RIGHT" and "side-BOTH".
Private.STICK_CLICK = [[
    local state = GetGamePadState()
    local buttons = state and state.buttons
    local leftIndex, rightIndex = self:GetAttribute("modifier-LEFT"), self:GetAttribute("modifier-RIGHT")
    local left = buttons and leftIndex and buttons[leftIndex]
    local right = buttons and rightIndex and buttons[rightIndex]
    local side = (left and right and "BOTH") or (left and "LEFT") or (right and "RIGHT") or "TOP"
    local target = self:GetAttribute("side-" .. side)
    if not target then return false end
    self:SetAttribute("macrotext", "/click " .. target .. " Gamepad 1\n/click " .. target .. " Gamepad")
]]
