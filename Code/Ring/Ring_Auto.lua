--[[
    Ring_Auto: keeps the menus current with the game. After any relevant event (bags, quests, toys,
    pet, equipment, spells, zone...), one update runs a moment later.
        1. It refills the built-in menus whose own events fired (Code\Ring\BuiltIns\*.lua, each
           listing the events it needs), in the order the user arranged them.
             - All of them refill at login and after hand edits. Ones that list no events always
               hold the same actions (whether each shows is step 3), so they only fill then.
             - While the settings are closed, only menus that can be opened in game (keybound, and
               their submenus) refill. The others are remembered, and refill when the settings
               open, where they're shown. Binding one, or adding it as a submenu, is an edit in the
               settings, which refills everything.
        2. It rebuilds when the state that secure attributes depend on changed, like the zone
           ability a zone ability action casts (Ring_Actions.GetAttributeSignature).
        3. It rebuilds when any action's visibility changed, an action bar's buttons too. The
           in-game menus leave out actions with nothing to fire (Ring_Actions.IsSliceAvailable).

    Rebuilds go through env.Event.DataChanged with reason env.ChangeReason.Auto, so they're quiet,
    and wait for combat to end if needed. Nothing can be rebuilt in combat, so the update waits.
    Events meanwhile are remembered, and one update runs when combat ends.
]]

local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Auto = env.AX_Modules:New("@\\Ring\\Auto")
local Perf = env.AX_Modules:Import("@\\Perf")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Setting = env.AX_Modules:Await("@\\Setting")

local UPDATE_DELAY = 0.25 -- coalesces bursts of bag, quest log and spell events

-- What visibility and the zone ability depend on, besides the built-in menus' own events.
local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE_DELAYED",       -- items
    "PLAYER_EQUIPMENT_CHANGED", -- equipped slots
    "UPDATE_EXTRA_ACTIONBAR",   -- Extra Action Button
    "PET_UI_UPDATE", "PET_BAR_UPDATE", -- pet spells and commands
    "SPELLS_CHANGED",           -- pet, zone ability
    "ZONE_CHANGED_NEW_AREA",    -- zone ability, housing Return
    "PLAYER_HOUSE_LIST_UPDATED", "HOUSE_PLOT_ENTERED", "HOUSE_PLOT_EXITED", -- housing (retail)
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", -- markers: group, leader and assistants
    "EQUIPMENT_SETS_CHANGED",   -- equipment sets
    -- Action bars: buttons filled or emptied, and Action Bar 1's page
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
}



-- Built-in menus

-- The built-in menu keys to refill (definition.key, saved as ring.builtin), or all of them. A menu
-- that can't be opened in game stays here until the settings open.
local dirtyKeys, refillAll = {}, true

--- Refills the dirty built-in menus that are in use. That's all of them while the settings are
--- open, else only those that can be opened in game, and the rest stay dirty.
---@return integer refilled how many were refilled (for the performance log)
local function RefillBuiltIns()
    local everything = Setting.GetHost and Setting.GetHost() ~= nil
    local _, openable = Ring_Data.GetOpenableRings()
    local refilled = 0
    for _, ring in ipairs(Ring_Data.GetRings()) do
        local key = ring.builtin
        if key and (refillAll or dirtyKeys[key]) then
            if everything or openable[ring.id] then
                Ring_Data.RefillBuiltIn(ring)
                dirtyKeys[key] = nil
                refilled = refilled + 1
            else
                dirtyKeys[key] = true
            end
        end
    end
    refillAll = false
    return refilled
end



-- Secure attribute state and visibility, remembered and rebuilt when they change

local lastAttributeSignature

-- Only menus that can be opened in game (keybound, and their submenus) are checked, because the
-- others have no in-game buttons to rebuild.

--- Whether a menu that can be opened in game holds an action of one of `kinds`.
---@param kinds table<string, boolean>
---@return boolean
local function HasSliceOfKinds(kinds)
    for _, ring in ipairs((Ring_Data.GetOpenableRings())) do
        for _, slice in ipairs(ring.slices) do
            if kinds[slice.kind] then return true end
        end
    end
    return false
end

-- Whether each action with a visibility rule is shown, in menu order. It's kept in one table and
-- compared in place on every update, so nothing is built to compare.
local availability, availabilityRead = {}, false

--- Reads every action's shown state into `availability`.
---@return boolean changed whether any changed
local function ReadAvailability()
    local changed, count = false, 0
    for _, ring in ipairs((Ring_Data.GetOpenableRings())) do
        for _, slice in ipairs(ring.slices) do
            if Ring_Actions.GetVisibilityCondition(slice) then
                count = count + 1
                local shown = Ring_Actions.IsSliceAvailable(slice) and true or false
                if availability[count] ~= shown then
                    availability[count] = shown
                    changed = true
                end
            end
        end
    end
    for index = #availability, count + 1, -1 do -- fewer actions than last time
        availability[index] = nil
        changed = true
    end
    return changed
end

--- Rebuilds when the secure attribute state or any action's visibility changed.
local function CheckGameState()
    local changed = false

    -- The first readings only remember, because the startup rebuild already used the current state.
    local signature, kinds = Ring_Actions.GetAttributeSignature()
    if signature ~= lastAttributeSignature then
        changed = lastAttributeSignature ~= nil and HasSliceOfKinds(kinds)
        lastAttributeSignature = signature
    end

    if ReadAvailability() and availabilityRead then changed = true end
    availabilityRead = true

    if changed then Ring_Data.NotifyDynamicChange() end
end



-- Update

local combatWaiter = CreateFrame("Frame")

--- Refills the built-in menus whose events fired, and rebuilds if the game state changed. In
--- combat, it waits until combat ends.
function Ring_Auto.Update()
    if not Ring_Data.IsReady() then return end
    -- Nothing can be rebuilt in combat, so what's dirty is kept, and it updates once combat ends.
    if InCombatLockdown() then
        combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local start = Perf.enabled and debugprofilestop()
    local refilled = RefillBuiltIns()
    CheckGameState()
    if start then Perf.CountUpdate(debugprofilestop() - start, refilled) end
end

combatWaiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Ring_Auto.Update()
end)

local updatePending = false

--- Updates in UPDATE_DELAY seconds, once for any number of calls meanwhile.
local function ScheduleUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(UPDATE_DELAY, function()
        updatePending = false
        Ring_Auto.Update()
    end)
end

--- Refills every built-in menu at the next update (not just the ones whose events fired).
local function ScheduleFullUpdate()
    refillAll = true
    ScheduleUpdate()
end

do
    local frame = CreateFrame("Frame")
    local keysByEvent = {} -- [event] = the built-in menu keys that refill after it
    local registered = {}
    local function Register(event)
        if registered[event] or not env.IsEventValid(event) then return end
        registered[event] = true
        frame:RegisterEvent(event)
    end
    for _, event in ipairs(EVENTS) do Register(event) end
    for _, definition in ipairs(Ring_Data.GetBuiltInDefinitions()) do
        for _, event in ipairs(definition.events or {}) do
            Register(event)
            if registered[event] then -- not for events this game doesn't have
                keysByEvent[event] = keysByEvent[event] or {}
                table.insert(keysByEvent[event], definition.key)
            end
        end
    end
    frame:RegisterUnitEvent("UNIT_PET", "player")
    frame:SetScript("OnEvent", function(_, event)
        if Perf.enabled then Perf.CountEvent(event) end
        -- After a login, reload or loading screen, everything may have changed.
        if event == "PLAYER_ENTERING_WORLD" then refillAll = true end
        local keys = keysByEvent[event]
        if keys then
            for _, key in ipairs(keys) do dirtyKeys[key] = true end
        end
        ScheduleUpdate()
    end)

    if ZoneAbilityFrame and ZoneAbilityFrame.UpdateDisplayedZoneAbilities then
        hooksecurefunc(ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", ScheduleUpdate)
    end
end

CallbackRegistry.Add(env.Event.DataReady, ScheduleFullUpdate)
-- Hand edits (an action added, a menu created) refill everything, in case they touched a
-- built-in menu's order.
CallbackRegistry.Add(env.Event.DataChanged, function(_, reason)
    if reason ~= env.ChangeReason.Auto then ScheduleFullUpdate() end
end)
-- When the settings open, the built-in menus left waiting refill (RefillBuiltIns), so the Library
-- and the preview show what they hold now.
CallbackRegistry.Add(Setting_Enum.Event.HostChanged, function(_, host)
    if host and next(dirtyKeys) then ScheduleUpdate() end
end)
-- Every rebuild uses the visibility of that moment. It's remembered, so only real changes rebuild.
CallbackRegistry.Add(env.Event.Rebuilt, function()
    ReadAvailability()
    availabilityRead = true
end)
