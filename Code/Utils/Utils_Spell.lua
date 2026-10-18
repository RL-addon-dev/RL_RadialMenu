--[[
    Spells and abilities: the player's spellbook, spell ranks, profession spells, the zone ability
    and the Extra Action Button.
]]

local env = select(2, ...)
local Utils_Spell = env.AX_Modules:New("@\\Utils\\Spell")

local GetSpellSubtext = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext

---@class SpellBookSpell
---@field name string
---@field icon number|string
---@field isPassive boolean
---@field isOffSpec boolean another specialization's spell
---@field flyoutID number? set for spells inside a flyout

--- Calls `callback(spellID, info)` for each spell you know inside flyout `flyoutID`.
---@param flyoutID number
---@param isOffSpec boolean whether the flyout is another specialization's
---@param callback fun(spellID: number, info: SpellBookSpell)
local function ForEachFlyoutSpell(flyoutID, isOffSpec, callback)
    local _, _, numSlots, isKnown = GetFlyoutInfo(flyoutID)
    if not (isKnown and numSlots) then return end
    for flyoutSlot = 1, numSlots do
        local spellID, overrideSpellID, slotKnown, spellName = GetFlyoutSlotInfo(flyoutID, flyoutSlot)
        -- A talent may replace the spell, so list what it casts now.
        if overrideSpellID and overrideSpellID > 0 then spellID = overrideSpellID end
        if spellID and slotKnown then
            callback(spellID, {
                name = C_Spell.GetSpellName(spellID) or spellName, icon = C_Spell.GetSpellTexture(spellID),
                isPassive = C_Spell.IsSpellPassive(spellID), isOffSpec = isOffSpec, flyoutID = flyoutID,
            })
        end
    end
end

--- Calls `callback` for the spellbook entry in `slot`: the spell itself, or the spells of a flyout.
---@param slot integer
---@param callback fun(spellID: number, info: SpellBookSpell)
local function VisitSpellBookItem(slot, callback)
    local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
    if not item then return end
    local types = Enum.SpellBookItemType
    if item.itemType == types.Spell and item.spellID then
        callback(item.spellID, {
            name = item.name, icon = item.iconID, isPassive = item.isPassive, isOffSpec = item.isOffSpec,
        })
    elseif item.itemType == types.Flyout and item.actionID then
        ForEachFlyoutSpell(item.actionID, item.isOffSpec, callback)
    end
end

--- Calls `callback(spellID, info)` for every spell in the player's spellbook, plus the known
--- spells inside its flyouts (Call Pet, Portals, the "Hero's Path" dungeon teleports), which
--- aren't spellbook entries of their own. Hidden skill lines are skipped.
---@param callback fun(spellID: number, info: SpellBookSpell)
function Utils_Spell.ForEachPlayerSpell(callback)
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if lineInfo and not lineInfo.shouldHide then
            local first = lineInfo.itemIndexOffset + 1
            for slot = first, first + lineInfo.numSpellBookItems - 1 do
                VisitSpellBookItem(slot, callback)
            end
        end
    end
end

--- A spell's rank, in game versions that have spell ranks (WoW Forever and Classic). Retail has
--- none, and there a spell's subtext is something else, such as "Racial".
---@param spellID any
---@return string? text the game's own rank text ("Rank 3")
---@return number? number
function Utils_Spell.GetSpellRank(spellID)
    if env.GAME_VERSION == env.GameVersion.Retail or type(spellID) ~= "number" or not GetSpellSubtext then
        return nil
    end
    local text = GetSpellSubtext(spellID)
    local number = text and tonumber(text:match("%d+"))
    if number then return text, number end
end

--- The castable spell ids of your professions, from the spellbook's Professions section. That's
--- your two primary professions, then Cooking, Fishing and Archaeology, each with the profession
--- itself (which opens its window) and its extra spells (Disenchant, Survey, ...). Passive entries
--- are left out. Empty where the client has no profession list (GetProfessions).
---
--- Cast these by id (the spell kind's `byId`). A profession's passive skill-line spell shares the
--- castable spell's name, so casting by name can pick the one that does nothing.
---@return number[]
function Utils_Spell.GetProfessionSpells()
    local spellIDs, seen = {}, {}
    if not (GetProfessions and GetProfessionInfo and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then
        return spellIDs
    end
    local bank, spellType = Enum.SpellBookSpellBank.Player, Enum.SpellBookItemType.Spell
    -- GetProfessions returns primary, primary, archaeology, fishing and cooking, nil where you
    -- have none.
    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
    local order = { prof1 or false, prof2 or false, cooking or false, fishing or false, archaeology or false }
    for _, profIndex in ipairs(order) do
        if profIndex then
            local _, _, _, _, numAbilities, spellOffset = GetProfessionInfo(profIndex)
            for slot = (spellOffset or 0) + 1, (spellOffset or 0) + (numAbilities or 0) do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                local spellID = item and item.itemType == spellType and not item.isPassive and item.spellID
                if spellID and not seen[spellID] then
                    seen[spellID] = true
                    spellIDs[#spellIDs + 1] = spellID
                end
            end
        end
    end
    return spellIDs
end

--- The zone ability the Zone Ability button currently shows (the lowest uiPriority).
---@return number? spellID the ability itself, which is what to cast (the game routes it on)
---@return number? shownID what it is right now, like the button shows it. Follower dungeons'
---     Dungeon Assistance, for example, turns into other spells as the dungeon goes on.
function Utils_Spell.GetZoneAbilitySpell()
    local abilities = C_ZoneAbility and C_ZoneAbility.GetActiveAbilities()
    local best
    for _, ability in ipairs(abilities or {}) do
        if ability.spellID and (not best or (ability.uiPriority or 0) < (best.uiPriority or 0)) then
            best = ability
        end
    end
    local spellID = best and best.spellID
    if not spellID then return nil end
    local override = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID)
    return spellID, ((override and override > 0) and override) or spellID
end

--- The action slot of the Extra Action Button while one is shown. It's read from the button itself
--- (working it out from the bar index can land on a normal action bar slot), and only while that
--- slot really holds an action.
---@return number?
function Utils_Spell.GetExtraActionSlot()
    if not (HasExtraActionBar and HasExtraActionBar()) then return nil end
    local button = ExtraActionButton1
    local slot = button and (button.action or (button.GetAttribute and button:GetAttribute("action")))
    if type(slot) == "number" and slot > 0 and HasAction(slot) then return slot end
end
