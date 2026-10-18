--[[
    The player's pet: whether there is one, its abilities, and what a pet action on the cursor is.

    A pet action on the cursor only reports ("petaction", 0), so this file remembers where the last
    one was picked up, by hooking the game's pickup functions.
]]

local env = select(2, ...)
local Utils_Pet = env.AX_Modules:New("@\\Utils\\Pet")

-- The pet bar's buttons.
Utils_Pet.NUM_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10

---@class PetSpell
---@field spellID number
---@field actionID number?
---@field name string
---@field icon number|string

---@class PetPickup where a pet action was picked up, one of these
---@field barSlot integer? from the pet bar
---@field bookSlot integer? from the pet spellbook
---@field spellID number? by spell id

--- Whether the player has a pet right now.
---@return boolean
function Utils_Pet.HasPet()
    return HasPetUI() and true or false
end

--- The current pet's castable abilities, from the pet spellbook. Pet entries are usually typed
--- PetAction rather than Spell. Commands and stances (Attack, Follow, Assist...) have no spell id,
--- so they aren't listed.
---@return PetSpell[]
function Utils_Pet.GetPetSpells()
    local spells = {}
    local bank = Enum.SpellBookSpellBank.Pet
    local types = Enum.SpellBookItemType
    for slot = 1, C_SpellBook.HasPetSpells() or 0 do
        local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
        if item and item.spellID and not item.isPassive
            and (item.itemType == types.Spell or item.itemType == types.PetAction) then
            spells[#spells + 1] = { spellID = item.spellID, actionID = item.actionID, name = item.name, icon = item.iconID }
        end
    end
    return spells
end



-- Pet actions on the cursor

---@type PetPickup?
local lastPetPickup
if PickupPetAction then
    hooksecurefunc("PickupPetAction", function(slot) lastPetPickup = { barSlot = slot } end)
end
if C_SpellBook.PickupSpellBookItem then
    hooksecurefunc(C_SpellBook, "PickupSpellBookItem", function(slot, bank)
        if bank == Enum.SpellBookSpellBank.Pet or bank == "pet" then
            lastPetPickup = { bookSlot = slot }
        end
    end)
end
if PickupPetSpell then
    hooksecurefunc("PickupPetSpell", function(spellID) lastPetPickup = { spellID = spellID } end)
end

--- Where the last pet action was picked up, for the debug output.
---@return PetPickup?
function Utils_Pet.GetLastPetPickup()
    return lastPetPickup
end

--- What the last picked up pet action is. That's either an ability (`spellID`), or a command or
--- stance (`name`, the pet bar token or the spellbook entry's localized name).
---@return { spellID: number }|{ name: string }|nil
function Utils_Pet.ResolvePetPickup()
    local pickup = lastPetPickup
    if not pickup then return nil end
    local spellID, name, isToken
    if pickup.spellID then
        spellID = pickup.spellID
    elseif pickup.barSlot then
        local actionName, _, token, _, _, _, actionSpellID = GetPetActionInfo(pickup.barSlot)
        name, isToken, spellID = actionName, token, actionSpellID
    elseif pickup.bookSlot then
        local item = C_SpellBook.GetSpellBookItemInfo(pickup.bookSlot, Enum.SpellBookSpellBank.Pet)
        if item then name, spellID = item.name, item.spellID end
    end

    if spellID and spellID > 0 and not isToken then return { spellID = spellID } end
    if name then return { name = name } end
end
