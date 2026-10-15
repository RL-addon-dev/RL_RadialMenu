--[[
    Keeps the menus current with the game. After any relevant event (bags, quests, toys, pet,
    equipment, spells, zone, ...), one update a moment later:

        1. refills the built-in menus whose own events fired (Code\Ring\BuiltIns\*.lua; each lists
           the events it needs), in the order the user arranged them. All of them at login and
           after hand edits; ones that list no events hold the same actions always (whether each
           shows is step 3), so they only fill then;
        2. rebuilds when the state that secure attributes depend on changed (the zone ability a
           zone ability slice casts: Ring_Actions.GetAttributeSignature);
        3. rebuilds when any action's visibility changed (Ring_Actions.IsSliceAvailable: the
           in-game menus leave out actions with nothing to fire), an action bar's buttons too.

    Rebuilds go through "Ring.DataChanged" with reason "auto": quiet, and after combat if needed.
    In combat nothing can be rebuilt, so the update waits: events meanwhile are remembered, and one
    update runs when combat ends.
]]

local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Auto = env.AX_Modules:New("@\\Ring\\Auto")

local UPDATE_DELAY = 0.25 -- coalesces bursts of bag / quest log / spell events

-- Besides the built-in menus' own events: what visibility and the zone ability depend on.
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
    -- Action bars: buttons filled / emptied, Action Bar 1's page
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
}



-- Built-in menus

-- Built-in menu keys to refill at the next update (definition.key = ring.builtin), or all of them.
local dirtyKeys, refillAll = {}, true

local function RefillBuiltIns()
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if ring.builtin and (refillAll or dirtyKeys[ring.builtin]) then Ring_Data.RefillBuiltIn(ring) end
    end
    wipe(dirtyKeys)
    refillAll = false
end



-- Secure attribute state and visibility: remembered as signatures, rebuilt when they change

local lastAttributeSignature, lastAvailability

-- Only menus that can be opened in game (keybound, and their submenus) are checked: the others
-- have no in-game buttons to rebuild.

local function HasSliceOfKinds(kinds)
    for _, ring in ipairs((Ring_Data.GetOpenableRings())) do
        for _, slice in ipairs(ring.slices) do
            if kinds[slice.kind] then return true end
        end
    end
end

--- One character per action with a visibility rule: whether it's shown right now.
local function GetAvailabilitySignature()
    local parts = {}
    local function Add(slice)
        if Ring_Actions.GetVisibilityCondition(slice) then
            parts[#parts + 1] = Ring_Actions.IsSliceAvailable(slice) and "1" or "0"
        end
    end
    for _, ring in ipairs((Ring_Data.GetOpenableRings())) do
        for _, slice in ipairs(ring.slices) do
            Add(slice)
        end
    end
    return table.concat(parts)
end

local function CheckGameState()
    local changed = false

    -- The first readings only remember: the startup rebuild already used the current state.
    local signature, kinds = Ring_Actions.GetAttributeSignature()
    if signature ~= lastAttributeSignature then
        changed = lastAttributeSignature ~= nil and HasSliceOfKinds(kinds)
        lastAttributeSignature = signature
    end

    local availability = GetAvailabilitySignature()
    if availability ~= lastAvailability then
        changed = changed or lastAvailability ~= nil
        lastAvailability = availability
    end

    if changed then Ring_Data.NotifyDynamicChange() end
end



-- Update

local combatWaiter = CreateFrame("Frame")

function Ring_Auto.Update()
    if not Ring_Data.IsReady() then return end
    -- Nothing can be rebuilt in combat: keep what's dirty, and update once it ends.
    if InCombatLockdown() then
        combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    RefillBuiltIns()
    CheckGameState()
end

combatWaiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Ring_Auto.Update()
end)

local updatePending = false
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
    local keysByEvent = {} -- event -> built-in menu keys that refill after it
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
        -- Login, reload and loading screens: everything may have changed.
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

CallbackRegistry.Add("Ring.DataReady", ScheduleFullUpdate)
-- Hand edits (a slice added, a menu created): refill in case they touched a built-in's order.
CallbackRegistry.Add("Ring.DataChanged", function(_, reason)
    if reason ~= "auto" then ScheduleFullUpdate() end
end)
-- Every rebuild uses the visibility of that moment; remember it so only real changes rebuild.
CallbackRegistry.Add("Ring.Rebuilt", function()
    lastAvailability = GetAvailabilitySignature()
end)
