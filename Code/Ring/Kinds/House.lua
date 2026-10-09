--[[
    house   home: "alliance" (Founder's Point) | "horde" (Razorwind Shores) | "return"
            Teleports to your house in that neighborhood (hidden while you don't own one there),
            or back to where you were before (hidden while the game doesn't offer it).

    Not a spell: the game's secure action types "teleporthome" (with the house's ids) and
    "returnhome". The ids aren't saved in the menu, they come from your house list
    (C_Housing.GetPlayerOwnedHouses, answered by PLAYER_HOUSE_LIST_UPDATED), so a menu works on
    every character and when shared. The menus rebuild when the list arrives
    (attributesChangeWith). Cooldowns are the Teleport Home / Return spells'.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local TELEPORT_SPELL = 1233637 -- Teleport Home
local RETURN_SPELL = 1270311   -- Return

-- Per home: the neighborhood (C_Housing.GetNeighborhoodTextureSuffix) and its zone (area id).
local HOMES = {
    alliance = { neighborhood = "elwynn", areaID = 16105, fallback = "Config - Rings - House - Alliance" },
    horde    = { neighborhood = "durotar", areaID = 15524, fallback = "Config - Rings - House - Horde" },
}
-- Plumber's icons: its Teleport Home and Leave Home macros (the Return spell itself shows a
-- generic hearthstone).
local HOME_ICON = 7252953
local RETURN_ICON = 236350

if env.GAME_VERSION ~= env.GameVersion.Retail then return end

-- Your houses by neighborhood ("elwynn" / "durotar"): { neighborhoodGUID, houseGUID, plotID }.
local houses = {}
do
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

--- Your house for `home` ("alliance" / "horde"), or nil.
local function GetHouse(home)
    local definition = HOMES[home]
    return definition and houses[definition.neighborhood]
end

--- Whether you own a house in `home`'s neighborhood (the Hearthstones menu lists those).
function Ring_Kinds.HasHouse(home)
    return GetHouse(home) ~= nil
end

local function GetNeighborhoodName(home)
    local definition = HOMES[home]
    return C_Map.GetAreaInfo(definition.areaID) or L[definition.fallback]
end

Ring_Kinds.Register({
    kind = "house",
    versions = { env.GameVersion.Retail },

    validate = function(slice)
        return HOMES[slice.home] ~= nil or slice.home == "return", "house needs a home (alliance, horde or return)"
    end,

    apply = function(button, suffix, slice)
        if slice.home == "return" then
            Ring_Kinds.SetAttribute(button, "type", suffix, "returnhome")
            return
        end
        local house = GetHouse(slice.home)
        if not house then
            Ring_Kinds.ClearAction(button, suffix)
            return
        end
        Ring_Kinds.SetAttribute(button, "type", suffix, "teleporthome")
        Ring_Kinds.SetAttribute(button, "house-neighborhood-guid", suffix, house.neighborhoodGUID)
        Ring_Kinds.SetAttribute(button, "house-guid", suffix, house.houseGUID)
        Ring_Kinds.SetAttribute(button, "house-plot-id", suffix, house.plotID)
    end,
    -- The attributes carry the house's ids: rebuild once the house list arrives or changes.
    attributesChangeWith = function()
        local alliance, horde = GetHouse("alliance"), GetHouse("horde")
        return (alliance and alliance.houseGUID or "") .. "/" .. (horde and horde.houseGUID or "")
    end,

    icon = function(slice)
        return slice.home == "return" and RETURN_ICON or HOME_ICON
    end,
    label = function(slice)
        if slice.home == "return" then
            return C_Spell.GetSpellName(RETURN_SPELL) or L["Config - Rings - House - Return"]
        end
        local teleport = C_Spell.GetSpellName(TELEPORT_SPELL) or L["Config - Rings - House - Teleport"]
        return format("%s: %s", teleport, GetNeighborhoodName(slice.home))
    end,

    cooldown = function(slice)
        return "spell", slice.home == "return" and RETURN_SPELL or TELEPORT_SPELL
    end,

    condition = function(slice) return slice.home == "return" and "housereturn" or "house" end,
    available = function(slice)
        if slice.home == "return" then return C_HousingNeighborhood.CanReturnAfterVisitingHouse() and true or false end
        return GetHouse(slice.home) ~= nil
    end,

    tooltip = function(tooltip, slice)
        tooltip:SetSpellByID(slice.home == "return" and RETURN_SPELL or TELEPORT_SPELL)
        if slice.home ~= "return" then tooltip:AddLine(GetNeighborhoodName(slice.home), 1, 1, 1) end
        return true
    end,

    search = {
        filter = "misc",
        label  = "house",
        events = { "PLAYER_HOUSE_LIST_UPDATED" },
        -- Your homes, then Return.
        scan   = function(add)
            for _, home in ipairs({ "alliance", "horde" }) do
                if GetHouse(home) then add({ kind = "house", home = home }) end
            end
            add({ kind = "house", home = "return" })
        end,
    },
})
