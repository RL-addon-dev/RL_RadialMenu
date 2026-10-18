--[[
    A spell. It's cast by name (the id's name when there's no `name`), so spec variants and talent
    replacements such as Kill Command resolve correctly. In game versions with spell ranks (WoW
    Forever), a ranked spell is cast by id instead, because by name the game always casts the
    highest rank.

    Spells you don't know (another class's, an untaken talent, a rank you haven't learned) are
    hidden in game. Pet abilities follow the pet instead.

    Two options change how it's cast.
        - anyRank casts the highest rank you know, by name (WoW Forever), so it upgrades itself as
          you learn ranks. `id` is then just one of its ranks.
        - byId always casts by id. Profession spells need it, because by name the game can pick the
          passive skill-line spell of the same name, which does nothing.
]]

---@class SpellSlice : Slice
---@field id number? the spell id (or `name`)
---@field name string? the spell name (or `id`)
---@field anyRank boolean? cast the highest rank you know (see the header)
---@field byId boolean? always cast by id (see the header)
---@field pet boolean? a pet ability, hidden while you have no pet

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Utils_Pet = env.AX_Modules:Import("@\\Utils\\Pet")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

--- Whether you know spell `id`.
---@param id number
---@return boolean
local function IsSpellKnown(id)
    return C_SpellBook.IsSpellKnown(id) and true or false
end

--- The pet ability id for cursor info from the pet spellbook or pet bar. The values differ by
--- source (spell id, pet action id, or pet bar slot), so each is checked against the pet
--- spellbook.
---@return number?
local function PetSpellFromCursor(...)
    local petSpells = Utils_Pet.GetPetSpells()
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "number" then
            for _, petSpell in ipairs(petSpells) do
                if value == petSpell.spellID or value == petSpell.actionID then return petSpell.spellID end
            end
        end
    end
    -- A pet bar slot (1 to 10) means the slot's ability.
    local slot = ...
    if type(slot) == "number" and slot >= 1 and slot <= Utils_Pet.NUM_ACTION_SLOTS then
        local spellID = select(7, GetPetActionInfo(slot))
        if spellID and spellID > 0 then return spellID end
    end
end

--- Ranked spells (WoW Forever). Each rank shows its rank under the name, like the spellbook, and
--- the ranks of one spell sort in order. `highest` collects the highest rank you know, by name.
local function NoteRank(candidate, spellID, name, icon, highest)
    local rankText, rank = Utils_Spell.GetSpellRank(spellID)
    if not rankText then return end
    candidate.note = rankText
    candidate.order = rank
    local best = highest[name]
    if name and (not best or rank > best.rank) then
        highest[name] = { id = spellID, rank = rank, icon = icon }
    end
end

--- Each ranked spell once more, not tied to a rank (cast by name, so your highest rank), listed
--- before its ranks (order 0). `fields` adds to the action (pet = true), and `kindLabel` replaces
--- the kind column's text (Pet Spell).
local function AddHighestRanks(add, highest, fields, kindLabel)
    for name, best in pairs(highest) do
        local slice = { kind = Ring_Kinds.Kind.Spell, id = best.id, anyRank = true }
        for key, value in pairs(fields or {}) do slice[key] = value end
        local candidate = add(slice, name, best.icon)
        if candidate then
            candidate.note = L["Config - Rings - Search - Note - HighestRank"]
            candidate.order = 0
            candidate.kindLabel = kindLabel
        end
    end
end

--- Spellbook spells, flyout spells included (Call Pet, Portals, ...).
local function ScanPlayerSpells(add, seen)
    local highest = {}
    Utils_Spell.ForEachPlayerSpell(function(spellID, info)
        if info.isPassive or seen[spellID] then return end
        seen[spellID] = true
        local candidate = add({ kind = Ring_Kinds.Kind.Spell, id = spellID }, info.name, info.icon)
        if not candidate then return end
        NoteRank(candidate, spellID, info.name, info.icon, highest)
        -- Other specializations' spells, for menus used in another spec, are listed after.
        if info.isOffSpec then
            candidate.group = 1
            candidate.note = L["Config - Rings - Search - Note - OtherSpec"]
        end
    end)
    AddHighestRanks(add, highest)
end

--- The current pet's abilities, saved as spell actions marked `pet`.
local function ScanPetSpells(add, seen)
    local highest = {}
    for _, petSpell in ipairs(Utils_Pet.GetPetSpells()) do
        if not seen[petSpell.spellID] then
            seen[petSpell.spellID] = true
            local name = petSpell.name or C_Spell.GetSpellName(petSpell.spellID)
            local slice = { kind = Ring_Kinds.Kind.Spell, id = petSpell.spellID, pet = true }
            local candidate = add(slice, name, petSpell.icon)
            if candidate then
                candidate.kindLabel = L["Config - Rings - Search - Kind - PetSpell"]
                NoteRank(candidate, petSpell.spellID, name, petSpell.icon, highest)
            end
        end
    end
    AddHighestRanks(add, highest, { pet = true }, L["Config - Rings - Search - Kind - PetSpell"])
end

--- The spell to cast and to ask about. That's its name, like /cast <name>, so the game uses
--- whatever version the spellbook has right now (spec variants, talent replacements). Some spells
--- don't work by id at all (Survival's Kill Command has no cast and no charges), so the id is only
--- the fallback when the name isn't known yet.
---@param slice SpellSlice
---@return string|number
local function SpellByName(slice)
    if slice.byId and slice.id then return slice.id end
    if not slice.anyRank and Utils_Spell.GetSpellRank(slice.id) then return slice.id end -- this exact rank
    return slice.name or C_Spell.GetSpellName(slice.id) or slice.id
end

--- Whether you can cast the spell the action casts. Cast by name, the name resolves only to
--- spells you know, whichever variant, replacement or rank that is. Cast by id (an exact rank,
--- a profession spell), that id must be known.
---@param slice SpellSlice
---@return boolean
local function IsKnown(slice)
    local spell = SpellByName(slice)
    if type(spell) == "string" then return C_Spell.GetSpellInfo(spell) ~= nil end -- nil for a name you don't know
    return IsSpellKnown(spell)
end

--- The spell id a tooltip shows. For a highest-rank spell, that's the rank its name resolves to now.
---@param slice SpellSlice
---@return number?
local function GetShownSpellID(slice)
    if slice.anyRank then
        local info = C_Spell.GetSpellInfo(SpellByName(slice))
        if info and info.spellID then return info.spellID end
    end
    return slice.id
end

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Spell,

    validate = function(slice)
        return slice.id ~= nil or slice.name ~= nil, L["Config - Rings - Edit - Error - Spell"]
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetSpell(button, suffix, SpellByName(slice))
    end,

    -- The icon, cooldown and charges of the version the spellbook has, like the cast. A name only
    -- resolves to spells you know, so another spec's spell falls back to its id's icon.
    icon  = function(slice)
        return C_Spell.GetSpellTexture(SpellByName(slice)) or (slice.id and C_Spell.GetSpellTexture(slice.id))
    end,
    ---@param slice SpellSlice
    label = function(slice)
        local spell = slice.name or slice.id --[[@as string|number]] -- validate makes sure one is set
        local name = C_Spell.GetSpellName(spell) or tostring(spell)
        local rankText = not slice.anyRank and Utils_Spell.GetSpellRank(slice.id)
        return (rankText and format("%s (%s)", name, rankText)) or name
    end,

    cooldown = function(slice) return Ring_Kinds.Source.Spell, SpellByName(slice) end,
    -- Not for pet abilities, because the player spell checks don't answer for them (they'd look
    -- unusable).
    ---@param slice SpellSlice
    state    = function(slice) if not slice.pet then return Ring_Kinds.Source.Spell, SpellByName(slice) end end,

    -- A spell you know has no rule at all, so there's no badge on every spell in the preview. One
    -- you don't know gets "known", and shows again once you learn it (Ring_Auto rebuilds on
    -- SPELLS_CHANGED).
    ---@param slice SpellSlice
    condition = function(slice)
        if slice.pet then return "pet" end
        if not IsKnown(slice) then return "known" end
    end,
    ---@param slice SpellSlice
    available = function(slice)
        if slice.pet then return Utils_Pet.HasPet() end
        return IsKnown(slice)
    end,

    tooltip = function(tooltip, slice)
        local spellID = GetShownSpellID(slice)
        if not spellID then return false end
        tooltip:SetSpellByID(spellID)
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
        local known = IsSpellKnown(id)
        local note = Utils_Spell.GetSpellRank(id)
        if not known then
            local notKnown = L["Config - Rings - Search - Note - NotKnown"]
            note = (note and (note .. "  ·  " .. notKnown)) or notKnown
        end
        return { kind = Ring_Kinds.Kind.Spell, id = id }, note
    end,

    cursor = {
        -- info1 is the spellbook slot, info2 the book type ("spell" or "pet"), info3 the spell id.
        spell = function(info1, info2, info3)
            local isPet = info2 == "pet"
            local spellID = info3
            if not spellID and info1 then
                local bank = (isPet and Enum.SpellBookSpellBank.Pet) or Enum.SpellBookSpellBank.Player
                local item = C_SpellBook.GetSpellBookItemInfo(info1, bank)
                spellID = item and item.spellID
            end
            if isPet then
                spellID = PetSpellFromCursor(info3, info1) or spellID
            elseif spellID and PetSpellFromCursor(spellID) == spellID then
                isPet = true -- a pet ability reported without the "pet" book type
            end
            if spellID then return { kind = Ring_Kinds.Kind.Spell, id = spellID, pet = isPet or nil } end
        end,
        -- From the pet spellbook or pet bar. An ability is handled here, a command or stance in
        -- Pet.lua.
        petaction = function(info1, info2, info3)
            local pickup = Utils_Pet.ResolvePetPickup()
            local spellID = (pickup and pickup.spellID) or PetSpellFromCursor(info1, info2, info3)
            if spellID then return { kind = Ring_Kinds.Kind.Spell, id = spellID, pet = true } end
        end,
    },
})
