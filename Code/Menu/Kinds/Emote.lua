--[[
    An emote, like /wave.
]]

---@class EmoteAction : Action
---@field token string the emote token, like "WAVE"

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

local ICON = "Interface\\Icons\\INV_Misc_Note_01" -- an emote without a symbol

-- Each offered emote's symbol (Menu_Kinds.GetSymbol, from Art\Symbols and game-icons.net). Similar
-- emotes share one, and the comment names that family. Other emotes show the note.
local SYMBOLS = {
    APPLAUD = "gloves",
    BOW     = "prayer",
    BYE     = "exit-door",
    CHEER   = "party-popper",
    CRY     = "tear-tracks",
    DANCE   = "ballerina-shoes",
    FLEX    = "muscle-up",
    HELLO   = "palm",            -- greeting
    HUG     = "embrassed-energy",
    KISS    = "lips",
    KNEEL   = "kneeling",
    LAUGH   = "witch-face",
    NO      = "thumb-down",
    NOD     = "thumb-up",
    POINT   = "pointing",
    ROAR    = "sonic-shout",
    SALUTE  = "swords-emblem",
    SIT     = "bar-stool",
    SLEEP   = "night-sleep",
    THANK   = "pay-money",
    TRAIN   = "subway-train",
    WAVE    = "palm",            -- greeting
}

-- Slash commands that aren't emote tokens of their own, like /yes, which is the NOD emote. Saved as
-- the command (its label), fired as the token, and shown with its symbol.
local ALIASES = {
    YES = "NOD",
}

-- Offered in the Add Action search (any token works in a saved menu).
local EMOTES = {
    "WAVE", "HELLO", "BYE", "BOW", "CHEER", "DANCE", "LAUGH", "THANK", "SALUTE", "APPLAUD",
    "ROAR", "FLEX", "KISS", "HUG", "CRY", "POINT", "NO", "YES", "SIT", "SLEEP", "KNEEL", "TRAIN"
}

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Emote,
    noIconBorder = true, -- the symbol on its own, not a spell

    ---@param action EmoteAction
    validate = function(action)
        return type(action.token) == "string", L["Config - Menus - Edit - Error - Emote"]
    end,

    ---@param action EmoteAction
    apply = function(button, suffix, action)
        local token = action.token:upper()
        Menu_Kinds.SetMacroText(button, suffix, ("/run DoEmote(%q)"):format(ALIASES[token] or token))
    end,

    ---@param action EmoteAction
    icon  = function(action)
        local token = action.token:upper()
        local symbol = SYMBOLS[token] or SYMBOLS[ALIASES[token]]
        return (symbol and Menu_Kinds.GetSymbol(symbol)) or ICON
    end,
    ---@param action EmoteAction
    label = function(action) return "/" .. action.token:lower() end,

    search = {
        filter = "emote",
        scan   = function(add)
            for _, token in ipairs(EMOTES) do add({ kind = Menu_Kinds.Kind.Emote, token = token }) end
        end,
    },
})
