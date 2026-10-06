--[[
    spell   id: number and/or name: string. Cast by name (the id's name if there's no `name`), so
            spec variants and talent replacements such as Kill Command resolve correctly. In game
            versions with spell ranks (WoW Forever), a ranked spell is cast by id instead: by
            name the game would always cast the highest rank
            pet: true for a pet ability (hidden while you have no pet)
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10

--- Pet ability id for cursor info from the pet spellbook or pet bar. The values differ by source
--- (spell id, pet action id, or pet bar slot), so each is checked against the pet spellbook.
local function PetSpellFromCursor(...)
    local petSpells = Ring_Kinds.GetPetSpells()
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "number" then
            for _, petSpell in ipairs(petSpells) do
                if value == petSpell.spellID or value == petSpell.actionID then return petSpell.spellID end
            end
        end
    end
    -- Pet bar slot (1-10): the slot's ability.
    local slot = ...
    if type(slot) == "number" and slot >= 1 and slot <= NUM_PET_ACTION_SLOTS then
        local spellID = select(7, GetPetActionInfo(slot))
        if spellID and spellID > 0 then return spellID end
    end
end

-- Spellbook spells, flyout spells included (Call Pet, Portals, ...).
local function ScanPlayerSpells(add, seen)
    Ring_Kinds.ForEachPlayerSpell(function(spellID, info)
        if info.isPassive or seen[spellID] then return end
        seen[spellID] = true
        local candidate = add({ kind = "spell", id = spellID }, info.name, info.icon)
        if not candidate then return end
        -- Ranked spells (WoW Forever): the rank under the name, like the spellbook, and the ranks
        -- of one spell in order.
        local rankText, rank = Ring_Kinds.GetSpellRank(spellID)
        if rankText then
            candidate.note = rankText
            candidate.order = rank
        end
        -- Other specializations' spells, for menus used in another spec: listed after.
        if info.isOffSpec then
            candidate.group = 1
            candidate.note = L["Config - Rings - Search - Note - OtherSpec"]
        end
    end)
end

-- Pet abilities (current pet), stored as spell slices marked `pet`.
local function ScanPetSpells(add, seen)
    for _, petSpell in ipairs(Ring_Kinds.GetPetSpells()) do
        if not seen[petSpell.spellID] then
            seen[petSpell.spellID] = true
            local name = petSpell.name or C_Spell.GetSpellName(petSpell.spellID)
            local candidate = add({ kind = "spell", id = petSpell.spellID, pet = true }, name, petSpell.icon)
            if candidate then candidate.kindLabel = L["Config - Rings - Search - Kind - PetSpell"] end
        end
    end
end

--- The spell to cast and to ask about: its name, like /cast <name>, so the game uses whatever
--- version the spellbook has right now (spec variants, talent replacements). Some spells don't
--- work by id at all (Survival's Kill Command: no cast, no charges); the id is only the fallback
--- when the name isn't known yet.
local function SpellByName(slice)
    if Ring_Kinds.GetSpellRank(slice.id) then return slice.id end -- this exact rank
    return slice.name or C_Spell.GetSpellName(slice.id) or slice.id
end

Ring_Kinds.Register({
    kind = "spell",

    validate = function(slice)
        return slice.id ~= nil or slice.name ~= nil, "spell needs an id or name"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetSpell(button, suffix, SpellByName(slice))
    end,

    -- Icon, cooldown and charges of the version the spellbook has, like the cast. A name only
    -- resolves to spells you know: another spec's spell falls back to its id's icon.
    icon  = function(slice)
        return C_Spell.GetSpellTexture(SpellByName(slice)) or (slice.id and C_Spell.GetSpellTexture(slice.id))
    end,
    label = function(slice)
        local name = C_Spell.GetSpellName(slice.name or slice.id) or tostring(slice.name or slice.id)
        local rankText = Ring_Kinds.GetSpellRank(slice.id)
        return rankText and format("%s (%s)", name, rankText) or name
    end,

    cooldown = function(slice) return "spell", SpellByName(slice) end,

    condition = function(slice) return slice.pet and "pet" or nil end,
    available = Ring_Kinds.HasPet,

    tooltip = function(tooltip, slice)
        if not slice.id then return false end
        tooltip:SetSpellByID(slice.id)
        return true
    end,

    search = {
        filter = "spell",
        events = { "SPELLS_CHANGED", "PET_BAR_UPDATE", "UNIT_PET", "PLAYER_SPECIALIZATION_CHANGED" },
        scan   = function(add)
            local seen = {}
            ScanPlayerSpells(add, seen)
            ScanPetSpells(add, seen)
        end,
    },

    lookupId = function(id)
        if not C_Spell.GetSpellName(id) then return nil end
        local known = IsPlayerSpell(id) or (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id))
        local note = Ring_Kinds.GetSpellRank(id)
        if not known then
            local notKnown = L["Config - Rings - Search - Note - NotKnown"]
            note = note and (note .. "  ·  " .. notKnown) or notKnown
        end
        return { kind = "spell", id = id }, note
    end,

    cursor = {
        spell = function(info1, info2, info3)
            -- info1 = spellbook slot, info2 = book type ("spell" / "pet"), info3 = spell id
            local isPet = info2 == "pet"
            local spellID = info3
            if not spellID and info1 then
                local bank = isPet and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                local item = C_SpellBook.GetSpellBookItemInfo(info1, bank)
                spellID = item and item.spellID
            end
            if isPet then
                spellID = PetSpellFromCursor(info3, info1) or spellID
            elseif spellID and PetSpellFromCursor(spellID) == spellID then
                isPet = true -- a pet ability reported without the "pet" book type
            end
            if spellID then return { kind = "spell", id = spellID, pet = isPet or nil } end
        end,
        -- From the pet spellbook or pet bar: an ability here, a command / stance in Pet.lua.
        petaction = function(info1, info2, info3)
            local pickup = Ring_Kinds.ResolvePetPickup()
            local spellID = pickup and pickup.spellID or PetSpellFromCursor(info1, info2, info3)
            if spellID then return { kind = "spell", id = spellID, pet = true } end
        end,
    },
})
