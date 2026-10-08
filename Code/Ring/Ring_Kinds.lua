--[[
    Action kinds: one definition per slice kind (Code\Ring\Kinds\<Kind>.lua, listed in
    Kinds\Kinds.xml), registered here. Everything kind-specific lives in its definition;
    Ring_Actions, Ring_Search, Ring_Data and Ring_Auto loop over them. Adding a kind means adding a
    file (plus its locale strings).

        Ring_Kinds.Register({
            kind      = "item",                                   -- slice.kind (required)
            versions  = { env.GameVersion.Retail },               -- games it exists in (env.GameVersion,
                                                                  -- Preload.lua; leave out for every version)
            validate  = function(slice, parentId) return ok, err end,  -- saved / added slices
            apply     = function(button, suffix, slice) end,      -- secure attributes (out of combat)
            icon      = function(slice, depth) return icon end,
            label     = function(slice) return text end,
            cooldown  = function(slice) return "spell" | "item" | "inventory", id end,
            state     = function(slice) return "spell" | "item" | "inventory", id end, -- icon states
                                                                  -- in game (usable, range, active, proc)
            condition = "item" | function(slice) return key end,  -- visibility rule: its locale key
            available = function(slice, depth) return boolean end, -- checked while `condition` is set
            tooltip   = function(tooltip, slice) return handled end, -- Add Action result rows
            search    = {                                         -- the Add Action panel
                filter  = "item",       -- which filter entry lists it (Ring_Search.Kinds)
                label   = "item",       -- kind column: "Config - Rings - Search - Kind - <label>" (default: kind)
                events  = { "BAG_UPDATE_DELAYED" },    -- rebuild the cached candidates on these
                scan    = function(add, ringId) end,   -- add(slice, name?, icon?) -> candidate
                                                       -- (name / icon default to the slice's label / icon)
                dynamic = true,         -- not cached (e.g. depends on the ring being edited)
            },
            lookupId  = function(id) return slice, note end,      -- a number typed in the search box
            cursor    = { item = function(info1, info2, info3) return slice end }, -- drag & drop, by cursor type
            attributesChangeWith = function() return value end,   -- apply() depends on game state:
                                                                  -- rings rebuild when this changes
            share     = {                                         -- sharing menus as text (Data\Share.lua);
                                                                  -- leave out: travels as is, then validate
                pack   = function(slice, macros) return slice end,  -- what travels; nil, reason: left out
                unpack = function(slice, plan) return slice end,    -- back into a menu; nil, reason: skipped
            },
        })

    Kind names are one lowercase word ("worldmarker", "equipslot"), not CamelCase like the code's
    own names: they're data, saved in every menu (slice.kind, and slice keys such as
    "targetmarker:8"), and they read like the game's own ids they sit next to (secure action types
    "worldmarker", "raidtarget"; cursor types "battlepet", "petaction"). Built-in menu keys follow
    the same rule (BuiltIn.lua). Renaming one after release needs a migration (Data\Migrations\).

    A kind for other game versions isn't registered: it isn't offered in Add Action, drag & drop
    or id lookups, and saved actions of that kind are hidden in game (Ring_Actions). A built-in menu
    must only use kinds that exist in all of its versions.

    A definition can also be search-only (Kinds\Profession.lua): just `search`, listing slices of
    another kind (spell actions) under its own filter; nothing is ever saved with its kind.

    Every field except `kind` is optional. Definitions are asked in registration order (filter
    entries, cursor handlers, id lookups), so each handler checks its own case (item skips toys).

    Also here: helpers shared by several definitions.
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:New("@\\Ring\\Kinds")

local order, byKind = {}, {}

Ring_Kinds.QUESTION_MARK_ICON = 134400

function Ring_Kinds.Register(definition)
    assert(type(definition.kind) == "string", "action kind needs a name")
    if not env.IsForThisGame(definition.versions) then return nil end
    assert(not byKind[definition.kind], "action kind registered twice: " .. definition.kind)
    byKind[definition.kind] = definition
    order[#order + 1] = definition
    return definition
end

function Ring_Kinds.Get(kind)
    return byKind[kind]
end

--- Every definition, in registration order.
function Ring_Kinds.All()
    return order
end



-- Secure attributes

-- Attributes use a "*" modifier wildcard so the slice still fires while the ring's modifier keys
-- (e.g. CTRL-SHIFT) are held on release.
function Ring_Kinds.SetAttribute(button, name, suffix, value)
    button:SetAttribute("*" .. name .. "-" .. suffix, value)
end

function Ring_Kinds.SetMacroText(button, suffix, text)
    Ring_Kinds.SetAttribute(button, "type", suffix, "macro")
    Ring_Kinds.SetAttribute(button, "macro", suffix, nil)
    Ring_Kinds.SetAttribute(button, "macrotext", suffix, text)
end

--- Casts `spell` (a name or id).
function Ring_Kinds.SetSpell(button, suffix, spell)
    Ring_Kinds.SetAttribute(button, "type", suffix, "spell")
    Ring_Kinds.SetAttribute(button, "spell", suffix, spell)
end

-- Hidden plain buttons for actions the game has no secure action type for (changing spec,
-- loading a talent build): the slice "clicks" one, and its OnClick makes the call. One per key,
-- created on first use (frames can't be destroyed; there are only a few).
local clickHandlers = {}

--- The slice runs `onClick()` (insecure code, so only for calls that aren't protected; the game
--- still refuses some of them in combat). `key` names the handler, e.g. "spec:250".
--- Must be called out of combat.
function Ring_Kinds.SetClick(button, suffix, key, onClick)
    local handler = clickHandlers[key]
    if not handler then
        handler = CreateFrame("Button", nil, UIParent)
        handler:Hide()
        clickHandlers[key] = handler
    end
    handler:SetScript("OnClick", function() onClick() end)
    Ring_Kinds.SetAttribute(button, "type", suffix, "click")
    Ring_Kinds.SetAttribute(button, "clickbutton", suffix, handler)
end

--- Nothing fires for this slice (e.g. a submenu, or a zone ability while there is none).
function Ring_Kinds.ClearAction(button, suffix)
    Ring_Kinds.SetAttribute(button, "type", suffix, nil)
end



-- Game state

function Ring_Kinds.HasPet()
    return HasPetUI() and true or false
end

--- The zone ability the Zone Ability button currently shows (lowest uiPriority).
--- @return number|nil spellID the ability itself (what to cast: the game routes it on)
--- @return number|nil shownID what it is right now, like the button shows it: follower dungeons'
---     Dungeon Assistance, for example, turns into other spells as the dungeon goes on
function Ring_Kinds.GetZoneAbilitySpell()
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
    return spellID, (override and override > 0) and override or spellID
end

--- Action slot of the Extra Action Button while one is shown. Read from the button itself (not
--- worked out from the bar index, which can land on a normal action bar slot), and only while
--- that slot really holds an action.
function Ring_Kinds.GetExtraActionSlot()
    if not (HasExtraActionBar and HasExtraActionBar()) then return nil end
    local button = ExtraActionButton1
    local slot = button and (button.action or (button.GetAttribute and button:GetAttribute("action")))
    if type(slot) == "number" and slot > 0 and HasAction(slot) then return slot end
end

--- The current pet's castable abilities from the pet spellbook. Pet entries are usually typed
--- PetAction rather than Spell; commands and stances (Attack, Follow, Assist...) have no spell id.
--- @return table list of { spellID, actionID, name, icon }
function Ring_Kinds.GetPetSpells()
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

--- Calls fn(spellID, info) for every spell in the player's spellbook, plus the known spells
--- inside its flyouts (Call Pet, Portals, the "Hero's Path" dungeon teleports), which aren't
--- spellbook entries of their own. Hidden skill lines are skipped.
---     info: name, icon, isPassive, isOffSpec (another specialization's), flyoutID (flyout spells)
function Ring_Kinds.ForEachPlayerSpell(fn)
    local bank = Enum.SpellBookSpellBank.Player
    local types = Enum.SpellBookItemType
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if lineInfo and not lineInfo.shouldHide then
            for slot = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if item and item.itemType == types.Spell and item.spellID then
                    fn(item.spellID, { name = item.name, icon = item.iconID, isPassive = item.isPassive, isOffSpec = item.isOffSpec })
                elseif item and item.itemType == types.Flyout and item.actionID then
                    local _, _, numSlots, isKnown = GetFlyoutInfo(item.actionID)
                    for flyoutSlot = 1, isKnown and numSlots or 0 do
                        local spellID, overrideSpellID, slotKnown, spellName = GetFlyoutSlotInfo(item.actionID, flyoutSlot)
                        -- A talent may replace the spell: list what it casts now.
                        if overrideSpellID and overrideSpellID > 0 then spellID = overrideSpellID end
                        if spellID and slotKnown then
                            fn(spellID, {
                                name = C_Spell.GetSpellName(spellID) or spellName, icon = C_Spell.GetSpellTexture(spellID),
                                isPassive = C_Spell.IsSpellPassive(spellID), isOffSpec = item.isOffSpec, flyoutID = item.actionID,
                            })
                        end
                    end
                end
            end
        end
    end
end

local GetSpellSubtext = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext

--- A spell's rank, in game versions that have spell ranks (WoW Forever, Classic; not retail,
--- where a spell's subtext is something else, such as "Racial").
--- @return string|nil text the game's own rank text ("Rank 3")
--- @return number|nil number
function Ring_Kinds.GetSpellRank(spellID)
    if env.GAME_VERSION == env.GameVersion.Retail or type(spellID) ~= "number" or not GetSpellSubtext then return nil end
    local text = GetSpellSubtext(spellID)
    local number = text and tonumber(text:match("%d+"))
    if number then return text, number end
end

local SpecInfo = C_SpecializationInfo or {}
local GetSpecialization = SpecInfo.GetSpecialization or GetSpecialization
local GetSpecializationInfo = SpecInfo.GetSpecializationInfo or GetSpecializationInfo
local GetNumSpecializations = SpecInfo.GetNumSpecializations or GetNumSpecializations

--- Calls fn(index, specID) for every specialization of the player's class, in the game's order.
function Ring_Kinds.ForEachSpec(fn)
    for index = 1, (GetNumSpecializations and GetNumSpecializations()) or 0 do
        local specID = GetSpecializationInfo(index)
        if specID then fn(index, specID) end
    end
end

--- The player's spec index for spec `specID` (nil when the class has no such spec).
function Ring_Kinds.GetSpecIndex(specID)
    for index = 1, (GetNumSpecializations and GetNumSpecializations()) or 0 do
        if GetSpecializationInfo(index) == specID then return index end
    end
end

--- Name, description and icon of spec `specID` (any class).
--- @return string|nil name, string|nil description, number|string|nil icon
function Ring_Kinds.GetSpecInfo(specID)
    if not GetSpecializationInfoByID then return nil end
    local _, name, description, icon = GetSpecializationInfoByID(specID)
    return name, description, icon
end

--- @return number|nil index, number|nil specID the player's current specialization
function Ring_Kinds.GetCurrentSpec()
    local index = GetSpecialization and GetSpecialization()
    if not index then return nil end
    return index, GetSpecializationInfo(index)
end

--- Castable spell ids of your professions, from the spellbook's Professions section: your two
--- primary professions, then Cooking, Fishing, Archaeology; each the profession itself (opens its
--- window) and its extra spells (Disenchant, Survey, ...). Passive entries are left out. Empty
--- where the client has no profession list (GetProfessions).
--- Cast these by id (spell `byId`): a profession's passive skill-line spell shares the castable
--- spell's name, so casting by name can pick the one that does nothing.
function Ring_Kinds.GetProfessionSpells()
    local spellIDs, seen = {}, {}
    if not (GetProfessions and GetProfessionInfo and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then
        return spellIDs
    end
    local bank, spellType = Enum.SpellBookSpellBank.Player, Enum.SpellBookItemType.Spell
    -- GetProfessions: primary, primary, archaeology, fishing, cooking (nil where you have none).
    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
    for _, profIndex in ipairs({ prof1 or false, prof2 or false, cooking or false, fishing or false, archaeology or false }) do
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

--- Whether item `itemID` is a toy you own (toys are their own action kind, not items).
function Ring_Kinds.IsToy(itemID)
    return PlayerHasToy(itemID) and C_ToyBox.GetToyInfo(itemID) ~= nil
end



-- Pet actions on the cursor

-- A pet action on the cursor reports only ("petaction", 0), so remember where it was picked up.
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

--- Where the last pet action was picked up (for the debug output).
function Ring_Kinds.GetLastPetPickup()
    return lastPetPickup
end

--- What the last picked up pet action is: an ability (spellID) or a command / stance (name, the
--- pet bar token or the spellbook entry's localized name).
--- @return table|nil { spellID = number } or { name = string }
function Ring_Kinds.ResolvePetPickup()
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
