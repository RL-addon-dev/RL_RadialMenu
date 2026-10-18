--[[
    Ring_Secure (see Snippets.lua): what the snippets call back (owner:CallMethod) for the insecure
    side of the flow: the view (Ring_View), scroll positions, Last Used, target markers aimed at the
    unit under the mouse, the controller's stick keys, and the menu held open (Rebuild.lua waits
    for it).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Live = env.AX_Modules:Import("@\\Ring\\Live")
local Ring_View = env.AX_Modules:Import("@\\Ring\\View")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")
local Utils_Unit = env.AX_Modules:Import("@\\Utils\\Unit")

local InCombatLockdown = InCombatLockdown
local Controller, Probe = Private.Controller, Private.Probe
local QUICK_SUFFIX = Private.QUICK_SUFFIX
local ringsById, buttonsById = Private.ringsById, Private.buttonsById
local GetMarkerMode = Private.GetMarkerMode

-- The menu held open right now (between OnRingOpen and OnRingClose), and since when. Rebuilds
-- wait until it's released. A Relaxed menu left open (OnRingRelaxed) waits for its click or
-- dismiss however long that takes: a rebuild would clear its bindings.
local openRingId, openSince, openRelaxed
local MAX_OPEN_TIME = 30 -- s; a held menu "open" longer than this missed its release: don't wait for it

--- Whether a rebuild must wait for the menu held open (Rebuild.lua).
function Private.IsMenuHeld()
    return openRingId ~= nil and (openRelaxed or GetTime() - openSince < MAX_OPEN_TIME)
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

--- Rebuilt (Setup.lua): `button`'s /tm lines are fresh, so a pending reset (ResetAimedMarkers)
--- has nothing to undo, and its old slot list may not match the new slots.
function Private.ForgetAimedMarkers(button)
    if aimedButton == button then aimedButton, aimedLive = nil, nil end
end

--- What each wedge shows, at the scroll positions the button holds.
local function GetDisplaySlices(live, button)
    local slices = {}
    for index = 1, #live.slices do
        local shown = GetLiveShownSlice(live, index, button:GetAttribute("ring-scroll-" .. index))
        slices[index] = ShowRedirect(live, button, shown)
    end
    return slices
end

-- A controller's open: the game sends the right stick's directions as keys (PADRSTICKUP, ...), which
-- keep the pick in combat (HELPER_CLICK "Aim"), only with GamePadStickAxisButtons on: switched on
-- while the menu is up, the player's own value put back after. The left stick's direction keys
-- aren't bound, and walking doesn't use them, so walking is unaffected.
local STICK_KEYS_SETTING = "GamePadStickAxisButtons"
local stickKeysSaved -- the value to put back, while switched on

local function SetStickKeys(on)
    local getter = (C_CVar and C_CVar.GetCVar) or GetCVar
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    if on and stickKeysSaved == nil then
        local value = getter(STICK_KEYS_SETTING)
        if value ~= nil and value ~= "1" and pcall(setter, STICK_KEYS_SETTING, "1") then
            stickKeysSaved = value
        end
    elseif not on and stickKeysSaved ~= nil then
        if pcall(setter, STICK_KEYS_SETTING, stickKeysSaved) then stickKeysSaved = nil end
    end
end

-- Called from the PRE_CLICK / HELPER_CLICK snippets (owner:CallMethod): insecure display and
-- bookkeeping for the secure flow. Positions are UIParent units.

--- @param relaxed boolean this open works like Relaxed (the setting, or a controller's click)
--- @param gamepad boolean opened by a controller's click: picks by the stick, the center otherwise
function Controller:OnRingOpen(ringId, startX, startY, relaxed, gamepad)
    local ring = ringsById[ringId]
    if not ring then return end

    openRingId, openSince, openRelaxed = ringId, GetTime(), false
    local button = buttonsById[ringId]
    -- Mark Target Markers On = Cursor: the unit hovered now, like a ping. "ring-aimed" tells
    -- the press snippet, which runs on after this, that it needn't steal your focus.
    if #ring.markerSuffixes > 0 and not InCombatLockdown() and GetMarkerMode() then
        local unit = Utils_Unit.GetUnitUnderMouse()
        if unit then
            AimMarkers(button, ring, unit)
            button:SetAttribute("ring-aimed", true)
            aimedButton, aimedLive = button, ring
        end
    end
    if gamepad then SetStickKeys(true) end
    local displaySlices = GetDisplaySlices(ring, button)
    local quickIndex = button:GetAttribute("ring-quick")
    local quickSlice = quickIndex == QUICK_SUFFIX and ShowRedirect(ring, button, ring.quickSlice)
        or (quickIndex and displaySlices[quickIndex])
    Ring_View:Open(ring, startX, startY, Probe, quickSlice, displaySlices, relaxed, gamepad and button)
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
            if slice.kind == Ring_Kinds.Kind.First then Ring_View:SetSliceIcon(other, shown) end
        end
        if live.quickSlice and live.quickSlice.kind == Ring_Kinds.Kind.First then Ring_View:SetQuickSlice(shown) end
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
    SetStickKeys(false)
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
    C_Timer.After(0, Private.QueueRebuild)
end
