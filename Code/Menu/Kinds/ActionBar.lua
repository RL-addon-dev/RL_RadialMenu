--[[
    Action bars. The Action Bar 1-8 library menus (Library\ActionBars.lua) hold their 12 buttons
    as action slots, and they're added to other menus as submenus (scrolled, or spread like a bar).
    They're listed in Add Action under Misc. Older saves held a whole bar as one action
    ("actionbar", Data\Migrations\003).

    An action slot fires the slot itself (the secure "action" type), whatever is on the bar, with
    its icon, cooldown, state and tooltip. It's hidden while the slot is empty, or while the bar is
    turned off in Options > Action Bars (not checked with a bar addon loaded, as they turn
    Blizzard's bars off).

    Action Bar 1 pages (stance or form, stealth, skyriding, vehicle, possess, override, Shift+1-6).
    A secure state driver keeps the page (PageFrame, its "state-page"), and Menu_Secure's release
    points a bar 1 button at that page's slot ("*pagedbutton-<suffix>" holds its button number), so
    it follows the page in combat too. Which buttons the menu has is decided out of combat, so a
    page change in combat can leave one empty until combat ends.

    Slots work like Blizzard's bars. Bar 1 uses page slots ((page - 1) * 12 + button), and the
    others are bar 2 61-72, bar 3 49-60, bar 4 25-36, bar 5 37-48, bar 6 145-156, bar 7 157-168 and
    bar 8 169-180.
]]

---@class ActionBarSlotAction : Action
---@field bar integer 1 to 8 (Edit Mode's Action Bar 1-8)
---@field button integer 1 to 12

local env = select(2, ...)
local L = env.L
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

local NUM_BARS = 8
local NUM_BUTTONS = 12
Menu_Kinds.NUM_ACTION_BARS, Menu_Kinds.NUM_ACTION_BUTTONS = NUM_BARS, NUM_BUTTONS
local FIRST_SLOT = { 1, 61, 49, 25, 37, 145, 157, 169 } -- bar 1 is page 1 (it pages)
local BAR_ADDONS = { "Bartender4", "Dominos", "ElvUI" }  -- they replace Blizzard's bars

--- Action Bar 1's page, by the same rules as the game's main bar (and Bartender's). That's the
--- override, vehicle, possess and temporary shapeshift bars first, then a page picked with
--- Shift+1-6, then the bonus bars (stances, forms, stealth, and 5 is skyriding).
---@return string conditions for RegisterStateDriver
local function GetPageConditions()
    local parts = {}
    local function Add(condition, page)
        if page and page > 0 then parts[#parts + 1] = condition .. " " .. page end
    end
    Add("[overridebar]", GetOverrideBarIndex and GetOverrideBarIndex())
    Add("[vehicleui]", GetVehicleBarIndex and GetVehicleBarIndex())
    Add("[possessbar]", GetVehicleBarIndex and GetVehicleBarIndex())
    Add("[shapeshift]", GetTempShapeshiftBarIndex and GetTempShapeshiftBarIndex())
    for page = 2, 6 do Add("[bar:" .. page .. "]", page) end
    for bonus = 1, 4 do Add("[bonusbar:" .. bonus .. "]", 6 + bonus) end
    Add("[bonusbar:5]", 11)
    parts[#parts + 1] = "1"
    return table.concat(parts, "; ")
end

local PageFrame = CreateFrame("Frame", "RLRM_ActionBarPage", UIParent, "SecureHandlerStateTemplate")
RegisterStateDriver(PageFrame, "page", GetPageConditions())
Menu_Kinds.ActionBarPageFrame = PageFrame -- Menu_Secure points bar 1 buttons at this page's slot

---@return integer
local function GetPage()
    return tonumber(PageFrame:GetAttribute("state-page")) or 1
end

--- The action slot button `button` of `bar` uses right now.
---@param bar integer
---@param button integer
---@return integer
local function GetSlot(bar, button)
    if bar == 1 then return (GetPage() - 1) * NUM_BUTTONS + button end
    return FIRST_SLOT[bar] + button - 1
end

---@return boolean
local function IsBarAddonLoaded()
    for _, name in ipairs(BAR_ADDONS) do
        if C_AddOns.IsAddOnLoaded(name) then return true end
    end
    return false
end

--- Whether `bar` is turned on in Options > Action Bars. Bar 1 always is, and so is every bar with a
--- bar addon.
---@param bar integer
---@return boolean
local function IsBarEnabled(bar)
    if bar == 1 or not GetActionBarToggles or IsBarAddonLoaded() then return true end
    -- Bars 2-8 in order. A client that reports fewer bars has no toggle for the rest.
    local toggles = { GetActionBarToggles() }
    if bar - 1 > #toggles then return true end
    return toggles[bar - 1] and true or false
end

--- What the slot's cooldown and state follow, its spell or item (for a macro, the spell it casts).
---@param action ActionBarSlotAction
---@return string? source Menu_Kinds.Source.Spell or Item
---@return (number|string)? id
local function GetSlotSource(action)
    local actionType, id, subType = GetActionInfo(GetSlot(action.bar, action.button))
    if actionType == "spell" and id then return Menu_Kinds.Source.Spell, id end
    if actionType == "item" and id then return Menu_Kinds.Source.Item, id end
    if actionType == "macro" and id then
        if subType == "spell" then return Menu_Kinds.Source.Spell, id end -- retail reports the macro's spell
        local spellID = GetMacroSpell(id)
        if spellID then return Menu_Kinds.Source.Spell, spellID end
    end
end

---@param bar any
---@return boolean
local function IsValidBar(bar)
    return type(bar) == "number" and bar >= 1 and bar <= NUM_BARS and bar % 1 == 0
end

Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.ActionSlot,

    ---@param action ActionBarSlotAction
    validate = function(action)
        return IsValidBar(action.bar) and type(action.button) == "number" and action.button >= 1 and action.button <= NUM_BUTTONS,
            L["Config - Menus - Edit - Error - ActionSlot"]
    end,

    ---@param action ActionBarSlotAction
    apply = function(button, suffix, action)
        Menu_Kinds.SetAction(button, suffix, "action", GetSlot(action.bar, action.button))
        -- Bar 1: Menu_Secure points it at the current page's slot when it fires.
        if action.bar == 1 then
            Menu_Kinds.SetSlotAttribute(button, Menu_Kinds.ActionAttribute.PagedButton, suffix, action.button)
        end
    end,

    ---@param action ActionBarSlotAction
    icon = function(action)
        return GetActionTexture(GetSlot(action.bar, action.button))
    end,
    ---@param action ActionBarSlotAction
    label = function(action)
        local slot = GetSlot(action.bar, action.button)
        local actionType, id = GetActionInfo(slot)
        local name
        if actionType == "spell" and id then
            name = C_Spell.GetSpellName(id)
        elseif actionType == "item" and id then
            name = C_Item.GetItemNameByID(id)
        elseif actionType then
            name = GetActionText(slot)
        end
        return name or format(L["Config - Menus - ActionBar - Button"], action.bar, action.button)
    end,

    cooldown = GetSlotSource,
    state    = GetSlotSource,

    condition = "actionslot",
    ---@param action ActionBarSlotAction
    available = function(action)
        return IsBarEnabled(action.bar) and HasAction(GetSlot(action.bar, action.button)) and true or false
    end,

    ---@param action ActionBarSlotAction
    tooltip = function(tooltip, action)
        local slot = GetSlot(action.bar, action.button)
        if not HasAction(slot) then return false end
        tooltip:SetAction(slot)
        return true
    end,
})

-- Search only (see Menu_Kinds.lua). The Action Bar library menus, as submenus, under Misc. They're
-- in Menus too, among every other menu.
Menu_Kinds.Register({
    kind = Menu_Kinds.Kind.ActionBarMenus,

    search = {
        filter  = "misc",
        label   = "actionbar",
        dynamic = true, -- the menus' ids
        scan    = function(add)
            for bar = 1, NUM_BARS do
                local menu = Menu_Data.GetActionBarMenu(bar)
                local candidate = menu and add({ kind = Menu_Kinds.Kind.Submenu, menu = menu.id }, menu.name)
                if candidate then
                    candidate.note = (bar == 1 and L["Config - Menus - ActionBar - Note - Paged"])
                        or format(L["Config - Menus - ActionBar - Note - Slots"], FIRST_SLOT[bar], FIRST_SLOT[bar] + NUM_BUTTONS - 1)
                end
            end
        end,
    },
})
