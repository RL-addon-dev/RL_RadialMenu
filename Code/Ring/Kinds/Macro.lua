--[[
    macro   name: macro name. Macros are written in the game's macro window.
]]

local env = select(2, ...)
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

--- The spell the macro would cast right now (its cooldown and state follow it).
local function MacroSpell(slice)
    local index = slice.name and GetMacroIndexByName(slice.name)
    local spellID = index and index > 0 and GetMacroSpell(index)
    if spellID then return "spell", spellID end
end

Ring_Kinds.Register({
    kind = "macro",

    validate = function(slice)
        return slice.name ~= nil, "macro needs a name"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetAttribute(button, "type", suffix, "macro")
        Ring_Kinds.SetAttribute(button, "macro", suffix, slice.name)
    end,

    icon  = function(slice) return select(2, GetMacroInfo(slice.name)) end,
    label = function(slice) return slice.name end,

    -- Follows the spell the macro would cast.
    cooldown = MacroSpell,
    state    = MacroSpell,

    search = {
        filter = "macro",
        events = { "UPDATE_MACROS" },
        -- Account macros, then character macros.
        scan   = function(add)
            local accountCount, characterCount = GetNumMacros()
            local maxAccount = MAX_ACCOUNT_MACROS or 120
            local function Add(index)
                local name, icon = GetMacroInfo(index)
                if name then add({ kind = "macro", name = name }, name, icon) end
            end
            for index = 1, accountCount do Add(index) end
            for index = maxAccount + 1, maxAccount + characterCount do Add(index) end
        end,
    },

    cursor = {
        macro = function(index)
            local name = GetMacroInfo(index)
            if name then return { kind = "macro", name = name } end
        end,
    },
})
