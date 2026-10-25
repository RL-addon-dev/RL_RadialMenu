--[[
    Teleports to your house in a neighborhood (hidden while you don't own one there), or back to
    where you were before (hidden while the game doesn't offer it).

    It isn't a spell. It uses the game's secure action types "teleporthome" (with the house's ids)
    and "returnhome". The ids aren't saved in the menu, they come from your house list
    (Utils_Housing), so a menu works on every character and when shared. The menus rebuild when the
    list arrives (attributesChangeWith). Cooldowns are the Teleport Utils_Housing.Home and Return spells'.
]]

---@class HouseAction : Action
---@field home string a Utils_Housing.Home value

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Housing = env.AX_Modules:Import("@\\Utils\\Housing")

local TELEPORT_SPELL = 1233637 -- Teleport Utils_Housing.Home
local RETURN_SPELL = 1270311   -- Return

-- The neighborhood's name when the game doesn't know its zone yet.
local FALLBACK_NAMES = {
    [Utils_Housing.Home.Alliance] = "Config - Menus - House - Alliance",
    [Utils_Housing.Home.Horde]    = "Config - Menus - House - Horde",
}
-- The Housing Dashboard's own teleport buttons (the spells themselves show a generic hearthstone).
local HOME_ICON = "atlas:dashboard-panel-homestone-teleport-button"
local RETURN_ICON = "atlas:dashboard-panel-homestone-teleport-out-button"

if env.GAME_VERSION ~= env.GameVersion.Retail then return end

---@param home string
---@return string
local function GetNeighborhoodName(home)
    return Utils_Housing.GetNeighborhoodName(home) or L[FALLBACK_NAMES[home]]
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.House,
    versions = { env.GameVersion.Retail },

    ---@param action HouseAction
    validate = function(action)
        local valid = Utils_Housing.IsNeighborhood(action.home) or action.home == Utils_Housing.Home.Return
        return valid, L["Config - Menus - Edit - Error - House"]
    end,

    ---@param action HouseAction
    apply = function(button, suffix, action)
        if action.home == Utils_Housing.Home.Return then
            Menu_Kinds.SetSlotAttribute(button, "type", suffix, "returnhome")
            return
        end
        local house = Utils_Housing.GetHouse(action.home)
        if not house then
            Menu_Kinds.ClearAction(button, suffix)
            return
        end
        Menu_Kinds.SetSlotAttribute(button, "type", suffix, "teleporthome")
        Menu_Kinds.SetSlotAttribute(button, "house-neighborhood-guid", suffix, house.neighborhoodGUID)
        Menu_Kinds.SetSlotAttribute(button, "house-guid", suffix, house.houseGUID)
        Menu_Kinds.SetSlotAttribute(button, "house-plot-id", suffix, house.plotID)
    end,
    -- The attributes carry the house's ids, so the menus rebuild once the house list arrives or
    -- changes.
    attributesChangeWith = function()
        local alliance = Utils_Housing.GetHouse(Utils_Housing.Home.Alliance)
        local horde = Utils_Housing.GetHouse(Utils_Housing.Home.Horde)
        return ((alliance and alliance.houseGUID) or "") .. "/" .. ((horde and horde.houseGUID) or "")
    end,

    ---@param action HouseAction
    icon = function(action)
        return (action.home == Utils_Housing.Home.Return and RETURN_ICON) or HOME_ICON
    end,
    ---@param action HouseAction
    label = function(action)
        if action.home == Utils_Housing.Home.Return then
            return C_Spell.GetSpellName(RETURN_SPELL) or L["Config - Menus - House - Return"]
        end
        local teleport = C_Spell.GetSpellName(TELEPORT_SPELL) or L["Config - Menus - House - Teleport"]
        return format("%s: %s", teleport, GetNeighborhoodName(action.home))
    end,

    ---@param action HouseAction
    cooldown = function(action)
        return Menu_Kinds.Source.Spell, (action.home == Utils_Housing.Home.Return and RETURN_SPELL) or TELEPORT_SPELL
    end,

    ---@param action HouseAction
    condition = function(action) return (action.home == Utils_Housing.Home.Return and "housereturn") or "house" end,
    ---@param action HouseAction
    available = function(action)
        if action.home == Utils_Housing.Home.Return then
            return C_HousingNeighborhood.CanReturnAfterVisitingHouse() and true or false
        end
        return Utils_Housing.HasHouse(action.home)
    end,

    ---@param action HouseAction
    tooltip = function(tooltip, action)
        tooltip:SetSpellByID((action.home == Utils_Housing.Home.Return and RETURN_SPELL) or TELEPORT_SPELL)
        if action.home ~= Utils_Housing.Home.Return then tooltip:AddLine(GetNeighborhoodName(action.home), 1, 1, 1) end
        return true
    end,

    search = {
        filter = "misc",
        label  = "house",
        events = { "PLAYER_HOUSE_LIST_UPDATED" },
        -- Your homes, then Return.
        scan   = function(add)
            for _, home in ipairs({ Utils_Housing.Home.Alliance, Utils_Housing.Home.Horde }) do
                if Utils_Housing.HasHouse(home) then add({ kind = Menu_Kinds.Kind.House, home = home }) end
            end
            add({ kind = Menu_Kinds.Kind.House, home = Utils_Housing.Home.Return })
        end,
    },
})
