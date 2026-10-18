--[[
    A macro, written in the game's macro window. Its cooldown and state follow the spell it would
    cast.
]]

---@class MacroSlice : Slice
---@field name string the macro's name

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

--- The spell the macro would cast right now.
---@param slice MacroSlice
---@return string? source Ring_Kinds.Source.Spell
---@return number? spellID
local function MacroSpell(slice)
    local index = slice.name and GetMacroIndexByName(slice.name)
    local spellID = index and index > 0 and GetMacroSpell(index)
    if spellID then return Ring_Kinds.Source.Spell, spellID end
end

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Macro,

    validate = function(slice)
        return slice.name ~= nil, L["Config - Rings - Edit - Error - Macro"]
    end,

    -- Shared with its text (Data\Share.lua), so the importer gets the macro, created if they
    -- don't have it.
    share = {
        pack = function(slice, macros)
            local _, icon, body = GetMacroInfo(slice.name or "")
            if not body then return nil, Ring_Data.ShareSkip.MissingMacro end
            macros[slice.name] = { icon = icon, body = body }
            return { kind = Ring_Kinds.Kind.Macro, name = slice.name }
        end,
        unpack = function(slice, plan)
            local name, reason = plan:ResolveMacro(slice.name)
            if not name then return nil, reason end
            slice.name = name
            return slice
        end,
    },

    apply = function(button, suffix, slice)
        Ring_Kinds.SetAction(button, suffix, "macro", slice.name)
    end,

    icon  = function(slice) return select(2, GetMacroInfo(slice.name)) end,
    label = function(slice) return slice.name end,

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
                if name then add({ kind = Ring_Kinds.Kind.Macro, name = name }, name, icon) end
            end
            for index = 1, accountCount do Add(index) end
            for index = maxAccount + 1, maxAccount + characterCount do Add(index) end
        end,
    },

    cursor = {
        macro = function(index)
            local name = GetMacroInfo(index)
            if name then return { kind = Ring_Kinds.Kind.Macro, name = name } end
        end,
    },
})
