--[[
    emote   token: emote token (e.g. "WAVE")
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\Icons\\INV_Misc_Note_01" -- an emote without a symbol

-- Each offered emote's symbol (Ring_Kinds.GetSymbol: Art\Symbols, from game-icons.net). Similar
-- emotes share one; the comment names that family. Other emotes show the note.
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

-- Slash commands that aren't emote tokens of their own: /yes is the NOD emote. Saved as the
-- command (its label), fired as the token, and shown with its symbol.
local ALIASES = {
    YES = "NOD",
}

-- Offered in the Add Action search (any token works in a saved menu).
local EMOTES = {
    "WAVE", "HELLO", "BYE", "BOW", "CHEER", "DANCE", "LAUGH", "THANK", "SALUTE", "APPLAUD",
    "ROAR", "FLEX", "KISS", "HUG", "CRY", "POINT", "NO", "YES", "SIT", "SLEEP", "KNEEL", "TRAIN"
}

Ring_Kinds.Register({
    kind = "emote",
    noIconBorder = true, -- the symbol on its own, not a spell

    validate = function(slice)
        return type(slice.token) == "string", "emote needs a token (e.g. WAVE)"
    end,

    apply = function(button, suffix, slice)
        local token = slice.token:upper()
        Ring_Kinds.SetMacroText(button, suffix, ("/run DoEmote(%q)"):format(ALIASES[token] or token))
    end,

    icon  = function(slice)
        local token = slice.token:upper()
        local symbol = SYMBOLS[token] or SYMBOLS[ALIASES[token]]
        return symbol and Ring_Kinds.GetSymbol(symbol) or ICON
    end,
    label = function(slice) return "/" .. slice.token:lower() end,

    search = {
        filter = "emote",
        scan   = function(add)
            for _, token in ipairs(EMOTES) do add({ kind = "emote", token = token }) end
        end,
    },
})
