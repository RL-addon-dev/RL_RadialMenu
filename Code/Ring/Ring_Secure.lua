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

    if down then
        -- Relaxed: the keybind again closes the open menu, firing nothing.
        if RELAXED_OPEN == ringId and OPEN_RING == ringId then
            OPEN_RING = nil
            OPEN_BUTTON = nil
            RELAXED_OPEN = nil
            helper:ClearBindings()
            probe:UnregisterAutoHide()
            probe:Hide()
            owner:CallMethod("OnRingClose", ringId, "cancel", nil)
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
    helper:ClearBindings()
    probe:UnregisterAutoHide()
    probe:Hide()
    result = result or "cancel"

    if index and self:GetAttribute("ring-quickmode") == "last" then
        self:SetAttribute("ring-quick", index)
    end

    owner:CallMethod("OnRingClose", ringId, result, index)
    if not index then return false end
    local suffix = "s" .. index
    if self:GetAttribute("ring-scrollcount-" .. index) then
        suffix = suffix .. "_" .. (self:GetAttribute("ring-scroll-" .. index) or 1)
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

local Helper = CreateFrame("Button", "RLRM_RingHelper", UIParent, "SecureActionButtonTemplate")
Helper:SetSize(1, 1)
Helper:EnableMouse(false)
Helper:RegisterForClicks("AnyDown")
SecureHandlerWrapScript(Helper, "OnClick", Controller, HELPER_CLICK)

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

--- What each wedge shows, at the scroll positions the button holds.
local function GetDisplaySlices(live, button)
    local slices = {}
    for index = 1, #live.slices do
        slices[index] = GetLiveShownSlice(live, index, button:GetAttribute("ring-scroll-" .. index))
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
    local displaySlices = GetDisplaySlices(ring, button)
    local quickIndex = button:GetAttribute("ring-quick")
    local quickSlice = quickIndex == QUICK_SUFFIX and ring.quickSlice or (quickIndex and displaySlices[quickIndex])
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
    if buttonsById[ringId]:GetAttribute("ring-quick") == index then Ring_View:SetQuickSlice(shown) end
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

    local live = ringsById[ringId]
    local button = buttonsById[ringId]
    local slice = live and index and live.slices[index]
    if slice and live.quickAction == Ring_Data.QuickAction.Last then
        Ring_Data.SetLastUsedKey(ringId, live.entries[index].key)
    end

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
        Ring_Actions.ApplySliceSuffix(button, "s" .. index .. "_" .. childIndex, childSlice)
    end
    return true
end

--- Must be called out of combat.
local function SetupRing(ring)
    local button = GetRingButton(ring.id)
    local live = Ring_Live.Build(ring)
    local count = #live.slices

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
    if live.quickSlice then
        -- Tap-only quick action: its attributes live under "sQ"; the snippet redirects a tap there.
        Ring_Actions.ApplySliceSuffix(button, "s" .. QUICK_SUFFIX, live.quickSlice)
        button:SetAttribute("ring-quickmode", "fixed")
        button:SetAttribute("ring-quick", QUICK_SUFFIX)
    elseif count == 1 then
        -- A single slice sits in the center (Ring_View), so a tap fires it too.
        button:SetAttribute("ring-quickmode", "fixed")
        button:SetAttribute("ring-quick", 1)
    else
        -- Quick action -> live index (nil while that slice is hidden). A fixed quick action on an
        -- expanded nested ring fires its first slice; Last Used is found by slice identity.
        local quick
        if ring.quickAction == Ring_Data.QuickAction.Last then
            local key = Ring_Data.GetLastUsedKey(ring.id)
            for index, entry in ipairs(live.entries) do
                if entry.key == key then quick = index break end
            end
        elseif type(ring.quickAction) == "number" then
            quick = live.firstOfTop[ring.quickAction]
        end
        button:SetAttribute("ring-quickmode", ring.quickAction == Ring_Data.QuickAction.Last and "last" or "fixed")
        button:SetAttribute("ring-quick", quick)
    end

    local hasScroll = false
    for index, slice in ipairs(live.slices) do
        Ring_Actions.ApplySlice(button, index, slice)
        if SetupNestedSlice(live, button, index, slice) then hasScroll = true end
    end
    button:SetAttribute("ring-hasscroll", hasScroll or nil)

    ringsById[ring.id] = live
    local binding, isAccount = Ring_Data.GetBinding(ring.id)
    button:SetAttribute("ring-keymods", GetModifierPrefix(binding))
    button:SetAttribute("ring-rightclick", Config.DBGlobal:GetVariable("RightClickDismiss") and true or nil)
    button:SetAttribute("ring-relaxed", Config.DBGlobal:GetVariable("MenuStyle") == env.Enum.MenuStyle.Relaxed or nil)
    if binding and (count > 0 or live.quickSlice) then
        pendingBindings[#pendingBindings + 1] = { key = binding, button = button:GetName(), account = isAccount }
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
    -- Account keybinds first: if a character menu uses the same key, it replaces them here.
    for pass = 1, 2 do
        for _, binding in ipairs(pendingBindings) do
            if binding.account == (pass == 1) then
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
-- Right-Click to Cancel decides whether held menus bind right click.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "RightClickDismiss", RequestRebuild)
-- Menu Style decides what the release and the mouse do.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "MenuStyle", RequestRebuild)
CallbackRegistry.Add("Config.Reset", RequestRebuild)
-- Open At, Select From = Menu Center, and the fixed menu's center live in secure attributes too.
CallbackRegistry.Add("Ring.DisplayMoved", function() RequestRebuild(nil, "auto") end)
