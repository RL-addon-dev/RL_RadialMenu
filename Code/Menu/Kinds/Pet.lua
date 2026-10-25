--[[
    A pet command or stance (Attack, Stay, Defensive...). It's hidden while you have no pet. Pet
    abilities are spell actions (Spell.lua).
]]

---@class PetAction : Action
---@field command string a PET_COMMANDS key, like "stay" (saved data, never renamed)

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Pet = env.AX_Modules:Import("@\\Utils\\Pet")

local FALLBACK_ICON = "Interface\\Icons\\Ability_Hunter_BeastCall"

-- Pet commands and stances. They're secure slash commands, so they work in combat. `tokens` are
-- the pet bar's action names (GetPetActionInfo), for drag and drop. `label` and `icon` name
-- Blizzard's globals. When one is missing, the label comes from the locale string
-- "Config - Menus - Pet - <key>".
local PET_COMMANDS = {
    { key = "attack",    slash = "/petattack",    label = "PET_ACTION_ATTACK",  icon = "PET_ATTACK_TEXTURE",    tokens = { "PET_ACTION_ATTACK" } },
    { key = "follow",    slash = "/petfollow",    label = "PET_ACTION_FOLLOW",  icon = "PET_FOLLOW_TEXTURE",    tokens = { "PET_ACTION_FOLLOW" } },
    { key = "stay",      slash = "/petstay",      label = "PET_ACTION_WAIT",    icon = "PET_WAIT_TEXTURE",      tokens = { "PET_ACTION_WAIT" } },
    { key = "moveto",    slash = "/petmoveto",    label = "PET_ACTION_MOVE_TO", icon = "PET_MOVE_TO_TEXTURE",   tokens = { "PET_ACTION_MOVE_TO" } },
    { key = "assist",    slash = "/petassist",    label = "PET_MODE_ASSIST",    icon = "PET_ASSIST_TEXTURE",    tokens = { "PET_MODE_ASSIST", "PET_MODE_AGGRESSIVE" } },
    { key = "defensive", slash = "/petdefensive", label = "PET_MODE_DEFENSIVE", icon = "PET_DEFENSIVE_TEXTURE", tokens = { "PET_MODE_DEFENSIVE", "PET_MODE_DEFENSIVEASSIST" } },
    { key = "passive",   slash = "/petpassive",   label = "PET_MODE_PASSIVE",   icon = "PET_PASSIVE_TEXTURE",   tokens = { "PET_MODE_PASSIVE" } },
}

local byKey, byToken = {}, {}
for _, command in ipairs(PET_COMMANDS) do
    byKey[command.key] = command
    for _, token in ipairs(command.tokens) do byToken[token] = command end
end

--- The pet command for a pet bar action token (like "PET_ACTION_WAIT"), or for its localized name.
---@param tokenOrName string
---@return table?
local function GetCommandByToken(tokenOrName)
    if byToken[tokenOrName] then return byToken[tokenOrName] end
    for token, command in pairs(byToken) do
        if _G[token] == tokenOrName then return command end
    end
end

--- The pet command or stance for cursor info from the pet bar (a slot whose action is a token
--- like PET_ACTION_WAIT) or the pet spellbook (an action id, matched by the entry's localized
--- name).
---@return table?
local function CommandFromCursor(...)
    local slot = ...
    if type(slot) == "number" and slot >= 1 and slot <= Utils_Pet.NUM_ACTION_SLOTS then
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

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Pet,

    ---@param action PetAction
    validate = function(action)
        return type(action.command) == "string", L["Config - Menus - Edit - Error - Pet"]
    end,

    ---@param action PetAction
    apply = function(button, suffix, action)
        local command = byKey[action.command]
        if command then
            Menu_Kinds.SetMacroText(button, suffix, command.slash)
        else
            Menu_Kinds.ClearAction(button, suffix)
        end
    end,

    ---@param action PetAction
    icon = function(action)
        local command = byKey[action.command]
        return (command and _G[command.icon]) or FALLBACK_ICON
    end,
    ---@param action PetAction
    label = function(action)
        local command = byKey[action.command]
        local key = tostring(action.command)
        return (command and _G[command.label]) or L["Config - Menus - Pet - " .. key] or key
    end,

    condition = "pet",
    available = Utils_Pet.HasPet,

    search = {
        filter = "pet",
        scan   = function(add)
            for _, command in ipairs(PET_COMMANDS) do
                add({ kind = Menu_Kinds.Kind.Pet, command = command.key })
            end
        end,
    },

    cursor = {
        -- A command or stance from the pet spellbook or pet bar. Abilities are handled in Spell.lua.
        petaction = function(info1, info2, info3)
            local pickup = Utils_Pet.ResolvePetPickup()
            local command = (pickup and pickup.name and GetCommandByToken(pickup.name))
                or CommandFromCursor(info1, info2, info3)
            if command then return { kind = Menu_Kinds.Kind.Pet, command = command.key } end
        end,
    },
})
