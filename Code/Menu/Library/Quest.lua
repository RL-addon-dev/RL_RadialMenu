--[[
    Quest Items: the items the quest log offers (the objective tracker's item buttons), plus usable
    quest items and quest starters in the bags. Each hides while you don't have it.

    The quest log part uses whichever quest log API the client has (C_QuestLog, or the older
    GetQuestLogTitle). Without quest log item buttons (GetQuestLogSpecialItemInfo), only the bags
    are searched.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Utils_Item = env.AX_Modules:Import("@\\Utils\\Item")

local GetNumEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or GetNumQuestLogEntries

--- Quest log entry `index`, its quest id and whether it's complete. Nil for a header.
---@param index integer
---@return number? questID
---@return boolean? isComplete
local function GetQuestEntry(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if not info or info.isHeader or not info.questID then return nil end
        return info.questID, C_QuestLog.IsComplete(info.questID)
    end
    -- The older API returns title, level, suggestedGroup, isHeader, isCollapsed, isComplete
    -- (1, -1 or nil), frequency and questID.
    local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(index)
    if not title or isHeader then return nil end
    return questID, isComplete == 1
end

-- Item ids found to be neither a quest item nor a quest starter. That never changes for an item,
-- so later scans skip the quest lookup for them (most of the bags).
local notQuest = {}

--- The quest items to offer, in quest log order, then bag order.
---@return number[] itemIDs
local function ScanQuestItems()
    local itemIDs, seen = {}, {}
    local function Add(itemID)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            itemIDs[#itemIDs + 1] = itemID
        end
    end

    -- Quest log items, which the objective tracker shows a button for.
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

    -- Usable quest items in the bags, and items that start a quest you don't have yet.
    Utils_Item.ForEachBagItem(function(bag, slot, itemID)
        if notQuest[itemID] then return end
        local info = C_Container.GetContainerItemQuestInfo(bag, slot)
        if not info.isQuestItem and not info.questID then
            notQuest[itemID] = true
        elseif (info.isQuestItem and C_Item.GetItemSpell(itemID)) or (info.questID and not info.isActive) then
            Add(itemID)
        end
    end)

    return itemIDs
end

Menu_Data.RegisterLibraryMenu({
    key      = "quest",
    category = Menu_Data.LibraryCategory.Situational,
    name     = "Config - Menus - QuestMenu - Name",
    versions = { env.GameVersion.Retail, env.GameVersion.Forever },
    -- Events a client doesn't have are skipped (Menu_Auto).
    events   = { "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" },
    scan     = function() return Menu_Data.MakeActions(Menu_Kinds.Kind.Item, ScanQuestItems()) end,
})
