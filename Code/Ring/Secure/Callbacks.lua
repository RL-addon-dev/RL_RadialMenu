--[[
    Ring_Secure (see Snippets.lua): what the snippets call back (owner:CallMethod) for the insecure
    side of the flow. That's the view (Ring_View), scroll positions, Last Used, target markers aimed
    at the unit under the mouse, the controller's stick keys, and the menu held open (Rebuild.lua
    waits for it).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Live = env.AX_Modules:Import("@\\Ring\\Live")
local Ring_View = env.AX_Modules:Import("@\\Ring\\View")
local Ring_Secure = env.AX_Modules:Import("@\\Ring\\Secure")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")
local Utils_Unit = env.AX_Modules:Import("@\\Utils\\Unit")

-- A held menu "open" longer than this (in seconds) missed its release, so rebuilds don't wait for it.
local MAX_OPEN_TIME = 30

-- A controller's open: the game sends the right stick's directions as keys (PADRSTICKUP, ...),
-- which keep the pick in combat (PRE_CLICK's "Aim"), only with this setting on. It's switched on
-- while the menu is up, and the player's own value put back after. The left stick's direction keys
-- aren't bound, and walking doesn't use them, so walking is unaffected.
local STICK_KEYS_SETTING = "GamePadStickAxisButtons"

-- What a Last Used or First Action fires, by its kind: the attribute holding its target wedge.
local REDIRECT_ATTRIBUTE = {
    [Ring_Kinds.Kind.LastUsed] = Ring_Secure.Attribute.Last,
    [Ring_Kinds.Kind.First]    = Ring_Secure.Attribute.First,
}

-- The menu held open right now (between OnRingOpen and OnRingClose), and since when. Rebuilds
-- wait until it's released. A Relaxed menu left open (OnRingRelaxed) waits for its click or
-- dismiss however long that takes, because a rebuild would clear its bindings.
local openRingId, openSince, openRelaxed

-- Target markers on the unit under the mouse when the menu opened: the button and live menu
-- whose marker slots point at it (nil while none do).
local aimedButton, aimedLive

local stickKeysSaved -- the setting's value to put back, while it's switched on

--- Whether a rebuild must wait for the menu held open (Rebuild.lua).
---@return boolean
function Private.IsMenuHeld()
    return openRingId ~= nil and (openRelaxed or GetTime() - openSince < MAX_OPEN_TIME)
end

--- The action live wedge `index` shows. A scroll submenu shows its current action. The indexes
--- usually come from secure attributes, which the editor types as strings, but hold numbers.
---@param live SecureLiveRing
---@param index any a wedge index
---@param scrollIndex any? a scroll submenu's shown action
---@return Slice?
local function GetLiveShownSlice(live, index, scrollIndex)
    local slice = live.slices[index]
    return slice and Ring_Live.GetShownSlice(slice, scrollIndex)
end

--- What `slice` shows, on a wedge or in the center. A Last Used or First Action shows what it
--- would fire now, and any other action (or one with nothing to fire) shows itself.
---@param live SecureLiveRing
---@param button Button
---@param slice Slice?
---@return Slice?
local function ShowRedirect(live, button, slice)
    local attribute = slice and REDIRECT_ATTRIBUTE[slice.kind]
    local target = attribute and button:GetAttribute(attribute)
    if not target then return slice end
    return GetLiveShownSlice(live, target, button:GetAttribute(Ring_Secure.Attribute.Scroll .. target)) or slice
end

--- Points live menu `live`'s target marker slots at `unit` (nil for your target). Out of combat.
---@param button Button
---@param live SecureLiveRing
---@param unit string?
local function AimMarkers(button, live, unit)
    for _, marker in ipairs(live.markerSuffixes) do
        Ring_Kinds.SetAttribute(button, "macrotext", marker.suffix, Ring_Kinds.GetTargetMarkerText(marker.id, unit))
    end
end

--- Points the aimed target markers back at your target.
local function ResetAimedMarkers()
    if not aimedButton or InCombatLockdown() then return end
    AimMarkers(aimedButton, aimedLive, nil)
    aimedButton:SetAttribute(Ring_Secure.Attribute.Aimed, nil)
    aimedButton, aimedLive = nil, nil
end

-- When combat starts, markers go back to your target while slots can still be changed.
local aimWatcher = CreateFrame("Frame")
aimWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
aimWatcher:SetScript("OnEvent", ResetAimedMarkers)

--- Called when `button` was rebuilt (Setup.lua). Its /tm lines are fresh, so a pending reset
--- (ResetAimedMarkers) has nothing to undo, and its old slot list may not match the new slots.
---@param button Button
function Private.ForgetAimedMarkers(button)
    if aimedButton == button then aimedButton, aimedLive = nil, nil end
end

--- What each wedge shows, at the scroll positions the button holds.
---@param live SecureLiveRing
---@param button Button
---@return Slice[]
local function GetDisplaySlices(live, button)
    local slices = {}
    for index = 1, #live.slices do
        local shown = GetLiveShownSlice(live, index, button:GetAttribute(Ring_Secure.Attribute.Scroll .. index))
        slices[index] = ShowRedirect(live, button, shown)
    end
    return slices
end

--- Switches the right stick's direction keys on (keeping the player's value) or back off.
---@param on boolean
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

--- The debug output for a pick: what fired, and the attributes the click used (the same suffix
--- as the PRE_CLICK snippet's).
---@param live SecureLiveRing?
---@param button Button
---@param result string
---@param index any a wedge index, or QUICK_SUFFIX
local function DebugPick(live, button, result, index)
    local scroll = type(index) == "number" and button:GetAttribute(Ring_Secure.Attribute.ScrollCount .. index)
        and button:GetAttribute(Ring_Secure.Attribute.Scroll .. index)
    local suffix = "s" .. index .. ((scroll and ("_" .. scroll)) or "")
    local fired = (index == Private.QUICK_SUFFIX and live and live.quickSlice)
        or (live and GetLiveShownSlice(live, index, scroll))
    local function Get(name) return tostring(button:GetAttribute("*" .. name .. "-" .. suffix)) end
    env.Debug(format("%s -> %s: %s | type=%s spell=%s item=%s macro=%s macrotext=%s action=%s marker=%s",
        result, suffix, (fired and Ring_Actions.GetLabel(fired)) or "?", Get("type"), Get("spell"),
        Get("item"), Get("macro"), Get("macrotext"), Get("action"), Get("marker")))
end



-- Called from the PRE_CLICK and HELPER_CLICK snippets (owner:CallMethod), for the insecure display
-- and bookkeeping of the secure flow. Positions are in UIParent units.

--- A menu opened.
---@param ringId string
---@param startX number
---@param startY number
---@param relaxed boolean this open works like Relaxed (the setting, or a controller's click)
---@param gamepad boolean opened by a controller's click, so it picks by the stick, else the center
function Private.Controller:OnRingOpen(ringId, startX, startY, relaxed, gamepad)
    local ring = Private.ringsById[ringId]
    if not ring then return end

    openRingId, openSince, openRelaxed = ringId, GetTime(), false
    local button = Private.buttonsById[ringId]
    -- Mark Target Markers On = Cursor: the unit hovered now, like a ping. "ring-aimed" tells the
    -- press snippet, which runs on after this, that it needn't steal your focus.
    if #ring.markerSuffixes > 0 and not InCombatLockdown() and Private.GetMarkerMode() then
        local unit = Utils_Unit.GetUnitUnderMouse()
        if unit then
            AimMarkers(button, ring, unit)
            button:SetAttribute(Ring_Secure.Attribute.Aimed, true)
            aimedButton, aimedLive = button, ring
        end
    end
    if gamepad then SetStickKeys(true) end
    local displaySlices = GetDisplaySlices(ring, button)
    local quickIndex = button:GetAttribute(Ring_Secure.Attribute.Quick)
    local quickSlice = (quickIndex == Private.QUICK_SUFFIX and ShowRedirect(ring, button, ring.quickSlice))
        or (quickIndex and displaySlices[quickIndex])
    Ring_View:Open(ring, startX, startY, Private.Probe, quickSlice, displaySlices, relaxed, gamepad and button)
end

--- The mouse wheel (or the D-pad) moved scroll wedge `index` to its action `current`. It's
--- remembered, and the wedge updated.
---@param ringId string
---@param index integer
---@param current integer
function Private.Controller:OnRingScroll(ringId, index, current)
    local live = Private.ringsById[ringId]
    if not live then return end

    local entry = live.entries[index]
    Ring_Data.SetScrollIndex(entry.ownerId, entry.ownerIndex, current)
    local shown = GetLiveShownSlice(live, index, current)
    Ring_View:SetSliceIcon(index, shown)
    -- The quick action is this scroll wedge, and a tap fires the action shown, so the center follows.
    local button = Private.buttonsById[ringId]
    if button:GetAttribute(Ring_Secure.Attribute.Quick) == index then Ring_View:SetQuickSlice(shown) end
    -- This is the first wedge, so First Actions fire (and show) the action shown now, on a wedge
    -- or in the center.
    if button:GetAttribute(Ring_Secure.Attribute.First) == index then
        for other, slice in ipairs(live.slices) do
            if slice.kind == Ring_Kinds.Kind.First then Ring_View:SetSliceIcon(other, shown) end
        end
        if live.quickSlice and live.quickSlice.kind == Ring_Kinds.Kind.First then Ring_View:SetQuickSlice(shown) end
    end
end

--- Relaxed: the keybind was released, and the menu stays open until a click or dismiss.
---@param ringId string
function Private.Controller:OnRingRelaxed(ringId)
    if openRingId ~= ringId then return end
    openRelaxed = true
end

--- A menu closed, with a pick or not.
---@param ringId string
---@param result string "slice", "quick" or "cancel"
---@param index (integer|string)? the live index, or QUICK_SUFFIX for the tap-only quick action
function Private.Controller:OnRingClose(ringId, result, index)
    Ring_View:Close()
    SetStickKeys(false)
    openRingId, openRelaxed = nil, false
    -- The pick fires after this returns, so the aimed markers are cleared just after it.
    if aimedButton then C_Timer.After(0, ResetAimedMarkers) end

    local live = Private.ringsById[ringId]
    local button = Private.buttonsById[ringId]
    -- Remembered for every menu, for Last Used actions (on a wedge or in the center).
    local slice = live and index and live.slices[index]
    if slice then Ring_Data.SetLastUsedKey(ringId, live.entries[index].key) end

    if env.DEBUG_MODE and index then
        DebugPick(live, button, result, index)
    else
        env.Debug(result)
    end

    -- A rebuild asked for while the menu was open runs next frame. This runs inside the release's
    -- snippet, before the chosen button is clicked.
    C_Timer.After(0, Private.QueueRebuild)
end
