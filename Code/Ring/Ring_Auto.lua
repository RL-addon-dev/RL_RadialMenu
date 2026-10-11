--[[
    Keeps the menus current with the game. After any relevant event (bags, quests, toys, pet,
    equipment, spells, zone, ...), one update a moment later:

        1. refills the built-in menus (Code\Ring\BuiltIns\*.lua; each lists the events it needs),
           in the order the user arranged them;
        2. rebuilds when the state that secure attributes depend on changed (the zone ability a
           zone ability slice casts: Ring_Actions.GetAttributeSignature);
        3. rebuilds when any action's visibility changed (Ring_Actions.IsSliceAvailable: the
           in-game menus leave out actions with nothing to fire), an action bar's buttons too.

    Rebuilds go through "Ring.DataChanged" with reason "auto": quiet, and after combat if needed.
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
    -- Action bars: buttons filled / emptied, Action Bar 1's page
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
}



-- Built-in menus

local function RefillBuiltIns()
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if ring.builtin then Ring_Data.RefillBuiltIn(ring) end
    end
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

--- One character per action with a visibility rule: whether it's shown right now. Actions that
--- spread (an action bar) add their own actions' (its buttons, filled or empty).
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
            for _, child in ipairs(Ring_Actions.GetSpreadSlices(slice) or {}) do Add(child) end
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

function Ring_Auto.Update()
    if not Ring_Data.IsReady() then return end
    RefillBuiltIns()
    CheckGameState()
end

local updatePending = false
local function ScheduleUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(UPDATE_DELAY, function()
        updatePending = false
        Ring_Auto.Update()
    end)
end

do
    local frame = CreateFrame("Frame")
    local registered = {}
    local function Register(event)
        if registered[event] or not env.IsEventValid(event) then return end
        registered[event] = true
        frame:RegisterEvent(event)
    end
    for _, event in ipairs(EVENTS) do Register(event) end
    for _, definition in ipairs(Ring_Data.GetBuiltInDefinitions()) do
        for _, event in ipairs(definition.events or {}) do Register(event) end
    end
    frame:RegisterUnitEvent("UNIT_PET", "player")
    frame:SetScript("OnEvent", ScheduleUpdate)

    if ZoneAbilityFrame and ZoneAbilityFrame.UpdateDisplayedZoneAbilities then
        hooksecurefunc(ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", ScheduleUpdate)
    end
end

CallbackRegistry.Add("Ring.DataReady", ScheduleUpdate)
-- Hand edits (a slice added, a menu created): refill in case they touched a built-in's order.
CallbackRegistry.Add("Ring.DataChanged", function(_, reason)
    if reason ~= "auto" then ScheduleUpdate() end
end)
-- Every rebuild uses the visibility of that moment; remember it so only real changes rebuild.
CallbackRegistry.Add("Ring.Rebuilt", function()
    lastAvailability = GetAvailabilitySignature()
end)
