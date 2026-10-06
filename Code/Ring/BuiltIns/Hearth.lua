--[[
    Hearthstones: the Hearthstone (while it's in your bags) and every hearthstone toy you own.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")

local HEARTHSTONE_ITEM = 6948

-- Hearthstone toys (item ids), in the order the menu lists them. The game has no "this is a
-- hearthstone" flag, so new ones need adding here; ids you don't own (or that don't exist on
-- this client) are skipped. Dalaran and Garrison Hearthstones last: they go somewhere else.
--
-- Keeping it up to date: Wowhead's spells whose description says they return you to your
-- hearthstone, https://www.wowhead.com/spells/name-extended:%22return+you+to+your+hearthstone%22
-- Open each new spell's "Used by item" and add that item if its tooltip says Toy (not quest
-- items, gear you equip, or consumables). Last checked October 2026.
local HEARTHSTONE_TOYS = {
    54452,  -- Ethereal Portal
    64488,  -- The Innkeeper's Daughter
    93672,  -- Dark Portal
    142542, -- Tome of Town Portal
    162973, -- Greatfather Winter's Hearthstone
    163045, -- Headless Horseman's Hearthstone
    163206, -- Weary Spirit Binding
    165669, -- Lunar Elder's Hearthstone
    165670, -- Peddlefeet's Lovely Hearthstone
    165802, -- Noble Gardener's Hearthstone
    166746, -- Fire Eater's Hearthstone
    166747, -- Brewfest Reveler's Hearthstone
    168907, -- Holographic Digitalization Hearthstone
    172179, -- Eternal Traveler's Hearthstone
    180290, -- Night Fae Hearthstone
    182773, -- Necrolord Hearthstone
    183716, -- Venthyr Sinstone
    184353, -- Kyrian Hearthstone
    188952, -- Dominated Hearthstone
    190196, -- Enlightened Hearthstone
    190237, -- Broker Translocation Matrix
    193588, -- Timewalker's Hearthstone
    200630, -- Ohn'ir Windsage's Hearthstone
    206195, -- Path of the Naaru
    208704, -- Deepdweller's Earthen Hearthstone
    209035, -- Hearthstone of the Flame
    210455, -- Draenic Hologem
    212337, -- Stone of the Hearth
    228940, -- Notorious Thread's Hearthstone
    235016, -- Redeployment Module
    236687, -- Explosive Hearthstone
    245970, -- P.O.S.T. Master's Express Hearthstone
    246565, -- Cosmic Hearthstone
    257736, -- Lightcalled Hearthstone
    263489, -- Naaru's Enfold
    263933, -- Preyseeker's Hearthstone
    264367, -- Mycomancer's Hearthspore
    265100, -- Corewarden's Hearthstone
    140192, -- Dalaran Hearthstone
    110560, -- Garrison Hearthstone
}

Ring_Data.RegisterBuiltIn({
    key    = "hearth",
    name   = "Config - Rings - HearthRing - Name",
    versions = { env.GameVersion.Retail },
    -- Toys load after login (TOYS_UPDATED).
    events = { "BAG_UPDATE_DELAYED", "TOYS_UPDATED", "NEW_TOY_ADDED" },
    scan   = function()
        local slices = {}
        if C_Item.GetItemCount(HEARTHSTONE_ITEM) > 0 then
            slices[1] = { kind = "item", id = HEARTHSTONE_ITEM }
        end
        for _, toyID in ipairs(HEARTHSTONE_TOYS) do
            if PlayerHasToy(toyID) then slices[#slices + 1] = { kind = "toy", id = toyID } end
        end
        return slices
    end,
})
