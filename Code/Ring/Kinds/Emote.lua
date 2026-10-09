--[[
    emote   token: emote token (e.g. "WAVE")
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- Each offered emote's icon (other emotes show the note).
local ICONS = {
    APPLAUD = 1386545, -- spell_priest_pontifex
    BOW     = 236308,  -- ability_warrior_furiousresolve
    BYE     = 590341,  -- pet_type_flying
    CHEER   = 6031602, -- inv_11xp_holiday_xmascracker01
    CRY     = 3750312, -- ui_embercourt-emoji-miserable
    DANCE   = 133886,  -- inv_misc_firedancer_01
    FLEX    = 236314,  -- ability_warrior_strengthofarms
    HELLO   = 3750314, -- ui_embercourt-emoji-veryhappy
    HUG     = 2021577, -- ability_racial_sympatheticvigor
    KISS    = 136209,  -- spell_shadow_soothingkiss
    KNEEL   = 642414,  -- ability_monk_legsweep
    LAUGH   = 3750310, -- ui_embercourt-emoji-elated
    NO      = 456031,  -- thumbsdown
    POINT   = 136157,  -- spell_shadow_fingerofdeath
    ROAR    = 463283,  -- spell_druid_stamedingroar
    SALUTE  = 1278391, -- inv_shield_1h_silverhand_b_01
    SIT     = 6403297, -- ui_campcollection
    SLEEP   = 136090,  -- spell_nature_sleep
    THANK   = 3750311, -- ui_embercourt-emoji-happy
    TRAIN   = 1029727, -- ability_foundryraid_traindeath
    WAVE    = 1360761, -- ability_paladin_handoflight
    YES     = 461267,  -- thumbsup
}

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

    icon  = function(slice) return ICONS[slice.token:upper()] or ICON end,
    label = function(slice) return "/" .. slice.token:lower() end,

    search = {
        filter = "emote",
        scan   = function(add)
            for _, token in ipairs(EMOTES) do add({ kind = "emote", token = token }) end
        end,
    },
})
