--[[
    Units and your group: whether you may set markers, and the unit under the mouse.
]]

local env = select(2, ...)
local Utils_Unit = env.AX_Modules:New("@\\Utils\\Unit")

local MAX_NAMEPLATES = 40

--- Whether you may set target and world markers in your group. Anyone can solo or in a party, and
--- in a raid only the leader and assistants can (or everyone, with "everyone is assistant").
---@return boolean
function Utils_Unit.CanSetMarkers()
    if not IsInRaid() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
        or (IsEveryoneAssistant and IsEveryoneAssistant()) or false
end

--- Whether `unit` is the unit under the mouse. This uses UnitIsUnit, not GUIDs, because Midnight
--- can hide a unit's GUID (a secret value) even out of combat. A secret answer counts as no.
---@param unit string
---@return boolean
local function IsMouseover(unit)
    local same = UnitIsUnit(unit, "mouseover")
    if issecretvalue and issecretvalue(same) then return false end
    return same and true or false
end

--- A unit token for the unit under the mouse that still names it once the mouse moves away (its
--- nameplate, target, focus, a group member, or you). Nil when there's nothing under the mouse, or
--- no such token. Call it out of combat.
---@return string?
function Utils_Unit.GetUnitUnderMouse()
    local candidates = { "target", "focus", "player" }
    -- Nameplate tokens directly (nameplate1 to 40), not through the plate frames, which can carry
    -- no token (nameplate addons, or Midnight).
    for index = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. index
        local exists = UnitExists(unit)
        if exists and not (issecretvalue and issecretvalue(exists)) then candidates[#candidates + 1] = unit end
    end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for index = 1, count do candidates[#candidates + 1] = prefix .. index end

    for _, unit in ipairs(candidates) do
        if IsMouseover(unit) then return unit end
    end
end
