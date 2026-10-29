--[[
    WoW API functions that moved between game versions. Retail keeps many of them in C_ namespaces
    (C_ActionBar.HasAction), while older clients like WoW Forever still have the global
    (HasAction). Each is looked up here once, so the rest of the addon uses one name on both.

        local HasAction = Utils_API.HasAction

    A field is nil when the client has neither (marked with ?), so check before calling those.
]]

local env = select(2, ...)
local Utils_API = env.AX_Modules:New("@\\Utils\\API")

--- The function in `namespace` when the client has it, else the global `name`. Each field below
--- gives its own type.
---@param namespace table?
---@param name string
---@return any
local function Get(namespace, name)
    return (namespace and namespace[name]) or _G[name]
end

-- Action bars

---@type fun(actionID: number): boolean
Utils_API.HasAction = Get(C_ActionBar, "HasAction")
---@type fun(actionID: number): fileID?
Utils_API.GetActionTexture = Get(C_ActionBar, "GetActionTexture")
---@type fun(actionID: number): string?
Utils_API.GetActionText = Get(C_ActionBar, "GetActionText")
---@type (fun(): number)?
Utils_API.GetOverrideBarIndex = Get(C_ActionBar, "GetOverrideBarIndex")
---@type (fun(): number)?
Utils_API.GetVehicleBarIndex = Get(C_ActionBar, "GetVehicleBarIndex")
---@type (fun(): number)?
Utils_API.GetTempShapeshiftBarIndex = Get(C_ActionBar, "GetTempShapeshiftBarIndex")
---@type (fun(): boolean)?
Utils_API.HasExtraActionBar = Get(C_ActionBar, "HasExtraActionBar")

-- Spells and items

---@type (fun(spell: number|string): string?)?
Utils_API.GetSpellSubtext = Get(C_Spell, "GetSpellSubtext")
-- Only the global: C_Spell.GetSpellInfo returns a table instead of the name.
---@type (fun(spell: number|string): string?)?
Utils_API.GetSpellInfo = Get(nil, "GetSpellInfo")
-- Only the global, since it's hooked by name (hooksecurefunc).
---@type (fun(spell: number|string))?
Utils_API.PickupSpell = Get(nil, "PickupSpell")
---@type (fun(item: number|string): string?)?
Utils_API.GetItemInfo = Get(C_Item, "GetItemInfo")

-- Specializations and quests

---@type (fun(specIndex: number): boolean?)?
Utils_API.SetSpecialization = Get(C_SpecializationInfo, "SetSpecialization")
---@type fun(): number
Utils_API.GetNumQuestLogEntries = Get(C_QuestLog, "GetNumQuestLogEntries")
-- Older clients only. Title, level, suggestedGroup, isHeader, isCollapsed, isComplete (1, -1 or
-- nil), frequency and questID.
---@type (fun(questLogIndex: number): string?, number, number, boolean, boolean, number?, number, number)?
Utils_API.GetQuestLogTitle = Get(nil, "GetQuestLogTitle")
