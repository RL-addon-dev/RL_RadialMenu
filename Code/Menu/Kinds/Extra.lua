--[[
    The Extra Action Button. It has no fields of its own, and it's hidden while there's none.
]]

local env = select(2, ...)
local L = env.L
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Spell = env.AX_Modules:Import("@\\Utils\\Spell")

-- Shown while there's no Extra Action. INV_Misc_Rune_01 was used before, but it's the
-- Hearthstone's icon.
local ICON = "Interface\\Icons\\INV_Scroll_03"

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Extra,
    versions = { env.GameVersion.Retail },

    apply = function(button, suffix)
        Menu_Kinds.SetMacroText(button, suffix, "/click ExtraActionButton1")
    end,

    icon = function()
        local slot = Utils_Spell.GetExtraActionSlot()
        return (slot and GetActionTexture(slot)) or ICON
    end,
    label = function()
        local slot = Utils_Spell.GetExtraActionSlot()
        -- Not `slot and GetActionInfo(slot)`: `and` keeps only the first value, so `id` was lost.
        local actionType, id
        if slot then actionType, id = GetActionInfo(slot) end
        local name = actionType == "spell" and id and C_Spell.GetSpellName(id)
        local title = L["Config - Menus - Special - Extra"]
        return (name and format("%s: %s", title, name)) or title
    end,

    condition = "extra",
    available = function() return Utils_Spell.GetExtraActionSlot() ~= nil end,

    search = {
        filter = "misc",
        label  = "special",
        events = { "UPDATE_EXTRA_ACTIONBAR" },
        scan   = Menu_Kinds.ScanOne(Menu_Kinds.Kind.Extra),
    },
})
