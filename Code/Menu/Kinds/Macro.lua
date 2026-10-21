--[[
    A macro, written in the game's macro window. Its cooldown and state follow the spell it would
    cast.
]]

---@class MacroAction : Action
---@field name string the macro's name

local env = select(2, ...)
local L = env.L
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

--- The spell the macro would cast right now.
---@param action MacroAction
---@return string? source Menu_Kinds.Source.Spell
---@return number? spellID
local function MacroSpell(action)
    local index = action.name and GetMacroIndexByName(action.name)
    local spellID = index and index > 0 and GetMacroSpell(index)
    if spellID then return Menu_Kinds.Source.Spell, spellID end
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.Macro,

    validate = function(action)
        return action.name ~= nil, L["Config - Menus - Edit - Error - Macro"]
    end,

    -- Shared with its text (Data\Share.lua), so the importer gets the macro, created if they
    -- don't have it.
    share = {
        pack = function(action, macros)
            local _, icon, body = GetMacroInfo(action.name or "")
            if not body then return nil, Menu_Data.ShareSkip.MissingMacro end
            macros[action.name] = { icon = icon, body = body }
            return { kind = Menu_Kinds.Kind.Macro, name = action.name }
        end,
        unpack = function(action, plan)
            local name, reason = plan:ResolveMacro(action.name)
            if not name then return nil, reason end
            action.name = name
            return action
        end,
    },

    apply = function(button, suffix, action)
        Menu_Kinds.SetAction(button, suffix, "macro", action.name)
    end,

    icon  = function(action) return select(2, GetMacroInfo(action.name)) end,
    label = function(action) return action.name end,

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
                if name then add({ kind = Menu_Kinds.Kind.Macro, name = name }, name, icon) end
            end
            for index = 1, accountCount do Add(index) end
            for index = maxAccount + 1, maxAccount + characterCount do Add(index) end
        end,
    },

    cursor = {
        macro = function(index)
            local name = GetMacroInfo(index)
            if name then return { kind = Menu_Kinds.Kind.Macro, name = name } end
        end,
    },
})
