--[[
    Quest Items: the items the quest log offers (the objective tracker's item buttons), plus
    usable quest items and quest starters in the bags. Each hides while you don't have it.

    WoW Forever has the older quest log API (GetQuestLogTitle) and no quest log item buttons:
    there, only the bags are searched. Each call below uses whichever the client has.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")

local GetNumEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or GetNumQuestLogEntries
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local GetContainerItemQuestInfo = (C_Container and C_Container.GetContainerItemQuestInfo) or GetContainerItemQuestInfo
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

--- Quest log entry `index`: its quest id and whether it's complete, or nil for a header.
local function GetQuestEntry(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if not info or info.isHeader or not info.questID then return nil end
        return info.questID, C_QuestLog.IsComplete(info.questID)
    end
    -- Older API: title, level, suggestedGroup, isHeader, isCollapsed, isComplete (1 / -1 / nil), frequency, questID
    local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(index)
    if not title or isHeader then return nil end
    return questID, isComplete == 1
end

--- What a bag slot's item is to quests. The older API returns values instead of a table.
--- @return boolean|nil isQuestItem, number|nil questID, boolean|nil isActive
local function GetBagItemQuestInfo(bag, slot)
    local info, questID, isActive = GetContainerItemQuestInfo(bag, slot)
    if type(info) == "table" then return info.isQuestItem, info.questID, info.isActive end
    return info, questID, isActive
end

--- Item ids, in quest log order, then bag order.
local function ScanQuestItems()
    local itemIDs, seen = {}, {}
    local function Add(itemID)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            itemIDs[#itemIDs + 1] = itemID
        end
    end

    -- Quest log items (what the objective tracker shows a button for).
    if GetQuestLogSpecialItemInfo then
        for index = 1, GetNumEntries() do
            local questID, isComplete = GetQuestEntry(index)
            if questID then
                local link, _, _, showWhenComplete = GetQuestLogSpecialItemInfo(index)
                if link and (showWhenComplete or not isComplete) then
                    Add(tonumber(link:match("item:(%d+)")))
                end
            end
        end
    end

    -- Bags: usable quest items, and items that start a quest you don't have yet.
    for bag = 0, LAST_BAG do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                local isQuestItem, questID, isActive = GetBagItemQuestInfo(bag, slot)
                if (isQuestItem and GetItemSpell(itemID)) or (questID and not isActive) then
                    Add(itemID)
                end
            end
        end
    end

    return itemIDs
end

Ring_Data.RegisterBuiltIn({
    key    = "quest",
    name   = "Config - Rings - QuestRing - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    -- Events a client doesn't have are skipped (Ring_Auto).
    events = { "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" },
    scan   = function()
        local slices = {}
        for i, itemID in ipairs(ScanQuestItems()) do slices[i] = { kind = "item", id = itemID } end
        return slices
    end,
})
