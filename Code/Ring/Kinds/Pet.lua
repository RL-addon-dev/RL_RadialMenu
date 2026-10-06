--[[
    pet     command: pet command / stance key from PET_COMMANDS below (e.g. "stay"); hidden while
            you have no pet
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10
local FALLBACK_ICON = "Interface\\Icons\\Ability_Hunter_BeastCall"

-- Pet commands and stances: secure slash commands, so they work in combat. `tokens` are the pet
-- bar's action names (GetPetActionInfo) for drag & drop; label / icon name Blizzard's globals.
local PET_COMMANDS = {
    { key = "attack",    slash = "/petattack",    label = "PET_ACTION_ATTACK",  icon = "PET_ATTACK_TEXTURE",    tokens = { "PET_ACTION_ATTACK" } },
    { key = "follow",    slash = "/petfollow",    label = "PET_ACTION_FOLLOW",  icon = "PET_FOLLOW_TEXTURE",    tokens = { "PET_ACTION_FOLLOW" } },
    { key = "stay",      slash = "/petstay",      label = "PET_ACTION_WAIT",    icon = "PET_WAIT_TEXTURE",      tokens = { "PET_ACTION_WAIT" } },
    { key = "moveto",    slash = "/petmoveto",    label = "PET_ACTION_MOVE_TO", icon = "PET_MOVE_TO_TEXTURE",   tokens = { "PET_ACTION_MOVE_TO" } },
    { key = "assist",    slash = "/petassist",    label = "PET_MODE_ASSIST",    icon = "PET_ASSIST_TEXTURE",    tokens = { "PET_MODE_ASSIST", "PET_MODE_AGGRESSIVE" } },
    { key = "defensive", slash = "/petdefensive", label = "PET_MODE_DEFENSIVE", icon = "PET_DEFENSIVE_TEXTURE", tokens = { "PET_MODE_DEFENSIVE", "PET_MODE_DEFENSIVEASSIST" } },
    { key = "passive",   slash = "/petpassive",   label = "PET_MODE_PASSIVE",   icon = "PET_PASSIVE_TEXTURE",   tokens = { "PET_MODE_PASSIVE" } },
}
local FALLBACK_LABELS = {
    attack = "Attack", follow = "Follow", stay = "Stay", moveto = "Move To",
    assist = "Assist", defensive = "Defensive", passive = "Passive"
}

local byKey, byToken = {}, {}
for _, command in ipairs(PET_COMMANDS) do
    byKey[command.key] = command
    for _, token in ipairs(command.tokens) do byToken[token] = command end
end

--- Pet command for a pet bar action token (e.g. "PET_ACTION_WAIT"), or for its localized name.
local function GetCommandByToken(tokenOrName)
    if byToken[tokenOrName] then return byToken[tokenOrName] end
    for token, command in pairs(byToken) do
        if _G[token] == tokenOrName then return command end
    end
end

--- Pet command / stance for cursor info from the pet bar (a slot whose action is a token like
--- PET_ACTION_WAIT) or the pet spellbook (an action id; matched by the entry's localized name).
local function CommandFromCursor(...)
    local slot = ...
    if type(slot) == "number" and slot >= 1 and slot <= NUM_PET_ACTION_SLOTS then
        local name, _, isToken = GetPetActionInfo(slot)
        local command = isToken and name and GetCommandByToken(name)
        if command then return command end
    end

    local bank = Enum.SpellBookSpellBank.Pet
    for slotIndex = 1, C_SpellBook.HasPetSpells() or 0 do
        local item = C_SpellBook.GetSpellBookItemInfo(slotIndex, bank)
        if item and item.actionID then
            for i = 1, select("#", ...) do
                if select(i, ...) == item.actionID then
                    local command = GetCommandByToken(item.name)
                    if command then return command end
                end
            end
        end
    end
end

Ring_Kinds.Register({
    kind = "pet",

    validate = function(slice)
        return type(slice.command) == "string", "pet command needs a command (e.g. attack)"
    end,

    apply = function(button, suffix, slice)
        local command = byKey[slice.command]
        if command then
            Ring_Kinds.SetMacroText(button, suffix, command.slash)
        else
            Ring_Kinds.ClearAction(button, suffix)
        end
    end,

    icon = function(slice)
        local command = byKey[slice.command]
        return command and _G[command.icon] or FALLBACK_ICON
    end,
    label = function(slice)
        local command = byKey[slice.command]
        return command and _G[command.label] or FALLBACK_LABELS[slice.command] or tostring(slice.command)
    end,

    condition = "pet",
    available = Ring_Kinds.HasPet,

    search = {
        filter = "pet",
        scan   = function(add)
            for _, command in ipairs(PET_COMMANDS) do
                add({ kind = "pet", command = command.key })
            end
        end,
    },

    cursor = {
        -- A command / stance from the pet spellbook or pet bar (abilities: Spell.lua).
        petaction = function(info1, info2, info3)
            local pickup = Ring_Kinds.ResolvePetPickup()
            local command = pickup and pickup.name and GetCommandByToken(pickup.name)
                or CommandFromCursor(info1, info2, info3)
            if command then return { kind = "pet", command = command.key } end
        end,
    },
})
