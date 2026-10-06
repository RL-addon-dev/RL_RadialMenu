--[[
    extra   (no fields) the Extra Action Button; hidden while there's none
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

-- Shown while there's no Extra Action (INV_Misc_Rune_01 was used before: it's the Hearthstone's icon).
local ICON = "Interface\\Icons\\INV_Scroll_03"

Ring_Kinds.Register({
    kind = "extra",
    versions = { env.GameVersion.Retail },

    validate = function() return true end,

    apply = function(button, suffix)
        Ring_Kinds.SetMacroText(button, suffix, "/click ExtraActionButton1")
    end,

    icon = function()
        local slot = Ring_Kinds.GetExtraActionSlot()
        return slot and GetActionTexture(slot) or ICON
    end,
    label = function()
        local slot = Ring_Kinds.GetExtraActionSlot()
        local actionType, id = slot and GetActionInfo(slot)
        local name = actionType == "spell" and id and C_Spell.GetSpellName(id)
        return name and format("%s: %s", L["Config - Rings - Special - Extra"], name) or L["Config - Rings - Special - Extra"]
    end,

    condition = "extra",
    available = function() return Ring_Kinds.GetExtraActionSlot() ~= nil end,

    search = {
        filter = "misc",
        label  = "special",
        events = { "UPDATE_EXTRA_ACTIONBAR" },
        scan   = function(add) add({ kind = "extra" }) end,
    },
})
