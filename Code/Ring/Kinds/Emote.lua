--[[
    emote   token: emote token (e.g. "WAVE")
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- Offered in the Add Action search (any token works in a saved menu).
local EMOTES = {
    "WAVE", "HELLO", "BYE", "BOW", "CHEER", "DANCE", "LAUGH", "THANK", "SALUTE", "APPLAUD",
    "ROAR", "FLEX", "KISS", "HUG", "CRY", "POINT", "NO", "YES", "SIT", "SLEEP", "KNEEL", "TRAIN"
}

Ring_Kinds.Register({
    kind = "emote",

    validate = function(slice)
        return type(slice.token) == "string", "emote needs a token (e.g. WAVE)"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetMacroText(button, suffix, ("/run DoEmote(%q)"):format(slice.token:upper()))
    end,

    icon  = function() return ICON end,
    label = function(slice) return "/" .. slice.token:lower() end,

    search = {
        filter = "emote",
        scan   = function(add)
            for _, token in ipairs(EMOTES) do add({ kind = "emote", token = token }) end
        end,
    },
})
