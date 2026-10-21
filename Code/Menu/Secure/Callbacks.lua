--[[
    Menu_Secure (see Snippets.lua): what the snippets call back (owner:CallMethod) for the insecure
    side of the flow. That's the view (Menu_View), scroll positions, Last Used, target markers aimed
    at the unit under the mouse, the controller's stick keys, and the menu held open (Rebuild.lua
    waits for it).
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Actions = env.AX_Modules:Import("@\\Menu\\Actions")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Live = env.AX_Modules:Import("@\\Menu\\Live")
local Menu_View = env.AX_Modules:Import("@\\Menu\\View")
local Menu_Secure = env.AX_Modules:Import("@\\Menu\\Secure")
local Private = env.AX_Modules:Import("@\\Menu\\Secure\\Private")
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
    [Menu_Kinds.Kind.LastUsed] = Menu_Secure.Attribute.Last,
    [Menu_Kinds.Kind.First]    = Menu_Secure.Attribute.First,
}

-- The menu held open right now (between OnMenuOpen and OnMenuClose), and since when. Rebuilds
-- wait until it's released. A Relaxed menu left open (OnMenuRelaxed) waits for its click or
-- dismiss however long that takes, because a rebuild would clear its bindings.
local openMenuId, openSince, openRelaxed

-- Target markers on the unit under the mouse when the menu opened: the button and live menu
-- whose marker slots point at it (nil while none do).
local aimedButton, aimedLive

local stickKeysSaved -- the setting's value to put back, while it's switched on

--- Whether a rebuild must wait for the menu held open (Rebuild.lua).
---@return boolean
function Private.IsMenuHeld()
    return openMenuId ~= nil and (openRelaxed or GetTime() - openSince < MAX_OPEN_TIME)
end

--- The action live wedge `index` shows. A scroll submenu shows its current action. The indexes
--- usually come from secure attributes, which the editor types as strings, but hold numbers.
---@param live SecureLiveMenu
---@param index any a wedge index
---@param scrollIndex any? a scroll submenu's shown action
---@return Action?
local function GetLiveShownAction(live, index, scrollIndex)
    local action = live.actions[index]
    return action and Menu_Live.GetShownAction(action, scrollIndex)
end

--- What `action` shows, on a wedge or in the center. A Last Used or First Action shows what it
--- would fire now, and any other action (or one with nothing to fire) shows itself.
---@param live SecureLiveMenu
---@param button Button
---@param action Action?
---@return Action?
local function ShowRedirect(live, button, action)
    local attribute = action and REDIRECT_ATTRIBUTE[action.kind]
    local target = attribute and button:GetAttribute(attribute)
    if not target then return action end
    return GetLiveShownAction(live, target, button:GetAttribute(Menu_Secure.Attribute.Scroll .. target)) or action
end

--- Points live menu `live`'s target marker slots at `unit` (nil for your target). Out of combat.
---@param button Button
---@param live SecureLiveMenu
---@param unit string?
local function AimMarkers(button, live, unit)
    for _, marker in ipairs(live.markerSuffixes) do
        Menu_Kinds.SetSlotAttribute(button, "macrotext", marker.suffix, Menu_Kinds.GetTargetMarkerText(marker.id, unit))
    end
end

--- Points the aimed target markers back at your target.
local function ResetAimedMarkers()
    if not aimedButton or InCombatLockdown() then return end
    AimMarkers(aimedButton, aimedLive, nil)
    aimedButton:SetAttribute(Menu_Secure.Attribute.Aimed, nil)
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
---@param live SecureLiveMenu
---@param button Button
---@return Action[]
local function GetDisplayActions(live, button)
    local actions = {}
    for index = 1, #live.actions do
        local shown = GetLiveShownAction(live, index, button:GetAttribute(Menu_Secure.Attribute.Scroll .. index))
        actions[index] = ShowRedirect(live, button, shown)
    end
    return actions
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
---@param live SecureLiveMenu?
---@param button Button
---@param result string
---@param index any a wedge index, or QUICK_SUFFIX
local function DebugPick(live, button, result, index)
    local scroll = type(index) == "number" and button:GetAttribute(Menu_Secure.Attribute.ScrollCount .. index)
        and button:GetAttribute(Menu_Secure.Attribute.Scroll .. index)
    local suffix = "s" .. index .. ((scroll and ("_" .. scroll)) or "")
    local fired = (index == Private.QUICK_SUFFIX and live and live.quickAction)
        or (live and GetLiveShownAction(live, index, scroll))
    local function Get(name) return tostring(button:GetAttribute("*" .. name .. "-" .. suffix)) end
    env.Debug(format("%s -> %s: %s | type=%s spell=%s item=%s macro=%s macrotext=%s action=%s marker=%s",
        result, suffix, (fired and Menu_Actions.GetLabel(fired)) or "?", Get("type"), Get("spell"),
        Get("item"), Get("macro"), Get("macrotext"), Get("action"), Get("marker")))
end



-- Called from the PRE_CLICK and HELPER_CLICK snippets (owner:CallMethod), for the insecure display
-- and bookkeeping of the secure flow. Positions are in UIParent units.

--- A menu opened.
---@param menuId string
---@param startX number
---@param startY number
---@param relaxed boolean this open works like Relaxed (the setting, or a controller's click)
---@param gamepad boolean opened by a controller's click, so it picks by the stick, else the center
function Private.Controller:OnMenuOpen(menuId, startX, startY, relaxed, gamepad)
    local menu = Private.menusById[menuId]
    if not menu then return end

    openMenuId, openSince, openRelaxed = menuId, GetTime(), false
    local button = Private.buttonsById[menuId]
    -- Mark Target Markers On = Cursor: the unit hovered now, like a ping. "menu-aimed" tells the
    -- press snippet, which runs on after this, that it needn't steal your focus.
    if #menu.markerSuffixes > 0 and not InCombatLockdown() and Private.GetMarkerMode() then
        local unit = Utils_Unit.GetUnitUnderMouse()
        if unit then
            AimMarkers(button, menu, unit)
            button:SetAttribute(Menu_Secure.Attribute.Aimed, true)
            aimedButton, aimedLive = button, menu
        end
    end
    if gamepad then SetStickKeys(true) end
    local displayActions = GetDisplayActions(menu, button)
    local quickIndex = button:GetAttribute(Menu_Secure.Attribute.Quick)
    local quickAction = (quickIndex == Private.QUICK_SUFFIX and ShowRedirect(menu, button, menu.quickAction))
        or (quickIndex and displayActions[quickIndex])
    Menu_View:Open(menu, startX, startY, Private.Probe, quickAction, displayActions, relaxed, gamepad and button)
end

--- The mouse wheel (or the D-pad) moved scroll wedge `index` to its action `current`. It's
--- remembered, and the wedge updated.
---@param menuId string
---@param index integer
---@param current integer
function Private.Controller:OnMenuScroll(menuId, index, current)
    local live = Private.menusById[menuId]
    if not live then return end

    local entry = live.entries[index]
    Menu_Data.SetScrollIndex(entry.ownerId, entry.ownerIndex, current)
    local shown = GetLiveShownAction(live, index, current)
    Menu_View:SetWedgeIcon(index, shown)
    -- The quick action is this scroll wedge, and a tap fires the action shown, so the center follows.
    local button = Private.buttonsById[menuId]
    if button:GetAttribute(Menu_Secure.Attribute.Quick) == index then Menu_View:SetQuickAction(shown) end
    -- This is the first wedge, so First Actions fire (and show) the action shown now, on a wedge
    -- or in the center.
    if button:GetAttribute(Menu_Secure.Attribute.First) == index then
        for other, action in ipairs(live.actions) do
            if action.kind == Menu_Kinds.Kind.First then Menu_View:SetWedgeIcon(other, shown) end
        end
        if live.quickAction and live.quickAction.kind == Menu_Kinds.Kind.First then Menu_View:SetQuickAction(shown) end
    end
end

--- Relaxed: the keybind was released, and the menu stays open until a click or dismiss.
---@param menuId string
function Private.Controller:OnMenuRelaxed(menuId)
    if openMenuId ~= menuId then return end
    openRelaxed = true
end

--- A menu closed, with a pick or not.
---@param menuId string
---@param result string "action", "quick" or "cancel"
---@param index (integer|string)? the live index, or QUICK_SUFFIX for the tap-only quick action
function Private.Controller:OnMenuClose(menuId, result, index)
    Menu_View:Close()
    SetStickKeys(false)
    openMenuId, openRelaxed = nil, false
    -- The pick fires after this returns, so the aimed markers are cleared just after it.
    if aimedButton then C_Timer.After(0, ResetAimedMarkers) end

    local live = Private.menusById[menuId]
    local button = Private.buttonsById[menuId]
    -- Remembered for every menu, for Last Used actions (on a wedge or in the center).
    local action = live and index and live.actions[index]
    if action then Menu_Data.SetLastUsedKey(menuId, live.entries[index].key) end

    if env.DEBUG_MODE and index then
        DebugPick(live, button, result, index)
    else
        env.Debug(result)
    end

    -- A rebuild asked for while the menu was open runs next frame. This runs inside the release's
    -- snippet, before the chosen button is clicked.
    C_Timer.After(0, Private.QueueRebuild)
end
