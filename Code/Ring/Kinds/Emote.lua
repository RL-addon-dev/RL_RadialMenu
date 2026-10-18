--[[
    An emote, like /wave.
]]

---@class EmoteSlice : Slice
---@field token string the emote token, like "WAVE"

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\Icons\\INV_Misc_Note_01" -- an emote without a symbol

-- Each offered emote's symbol (Ring_Kinds.GetSymbol, from Art\Symbols and game-icons.net). Similar
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

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Emote,
    noIconBorder = true, -- the symbol on its own, not a spell

    ---@param slice EmoteSlice
    validate = function(slice)
        return type(slice.token) == "string", L["Config - Rings - Edit - Error - Emote"]
    end,

    ---@param slice EmoteSlice
    apply = function(button, suffix, slice)
        local token = slice.token:upper()
        Ring_Kinds.SetMacroText(button, suffix, ("/run DoEmote(%q)"):format(ALIASES[token] or token))
    end,

    ---@param slice EmoteSlice
    icon  = function(slice)
        local token = slice.token:upper()
        local symbol = SYMBOLS[token] or SYMBOLS[ALIASES[token]]
        return (symbol and Ring_Kinds.GetSymbol(symbol)) or ICON
    end,
    ---@param slice EmoteSlice
    label = function(slice) return "/" .. slice.token:lower() end,

    search = {
        filter = "emote",
        scan   = function(add)
            for _, token in ipairs(EMOTES) do add({ kind = Ring_Kinds.Kind.Emote, token = token }) end
        end,
    },
})
