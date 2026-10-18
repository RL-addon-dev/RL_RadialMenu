--[[
    Player housing (retail): your houses, by neighborhood. The game sends the list on request
    (C_Housing.GetPlayerOwnedHouses, answered by PLAYER_HOUSE_LIST_UPDATED), so this file asks
    once you're in the world and keeps the latest answer.
]]

local env = select(2, ...)
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Utils_Housing = env.AX_Modules:New("@\\Utils\\Housing")

-- Where the house actions go, by the key menus save (the house kind's `home`). These values are
-- saved data, so never rename one.
Utils_Housing.Home = Utils_Standard.Strict({
    Alliance = "alliance", -- your house in Founder's Point
    Horde    = "horde",    -- your house in Razorwind Shores
    Return   = "return",   -- back to where you were before visiting a house (not a neighborhood)
}, "home")

-- Per home, its neighborhood (C_Housing.GetNeighborhoodTextureSuffix) and its zone (area id).
local NEIGHBORHOODS = {
    [Utils_Housing.Home.Alliance] = { neighborhood = "elwynn", areaID = 16105 },
    [Utils_Housing.Home.Horde]    = { neighborhood = "durotar", areaID = 15524 },
}

---@class OwnedHouse
---@field neighborhoodGUID string
---@field houseGUID string
---@field plotID number

---@type table<string, OwnedHouse> your houses, by neighborhood ("elwynn" or "durotar")
local houses = {}

if env.GAME_VERSION == env.GameVersion.Retail then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    frame:SetScript("OnEvent", function(self, event, list)
        if event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            C_Housing.GetPlayerOwnedHouses() -- answered by PLAYER_HOUSE_LIST_UPDATED
            return
        end
        wipe(houses)
        for _, info in ipairs(list or {}) do
            local neighborhood = info.neighborhoodGUID and C_Housing.GetNeighborhoodTextureSuffix(info.neighborhoodGUID)
            if neighborhood then houses[neighborhood] = info end
        end
    end)
end

--- Whether `home` is a neighborhood you can have a house in (Alliance or Horde, not Return).
---@param home any
---@return boolean
function Utils_Housing.IsNeighborhood(home)
    return NEIGHBORHOODS[home] ~= nil
end

--- Your house for `home`, or nil.
---@param home string a Utils_Housing.Home value
---@return OwnedHouse?
function Utils_Housing.GetHouse(home)
    local definition = NEIGHBORHOODS[home]
    return definition and houses[definition.neighborhood]
end

--- Whether you own a house in `home`'s neighborhood.
---@param home string a Utils_Housing.Home value
---@return boolean
function Utils_Housing.HasHouse(home)
    return Utils_Housing.GetHouse(home) ~= nil
end

--- The zone name of `home`'s neighborhood, or nil when the game doesn't know it.
---@param home string a Utils_Housing.Home value
---@return string?
function Utils_Housing.GetNeighborhoodName(home)
    local definition = NEIGHBORHOODS[home]
    return definition and C_Map.GetAreaInfo(definition.areaID) or nil
end
