--[[
    Two kinds: a whole action bar, and one of its buttons.

    actionbar   bar: 1-8 (Edit Mode's Action Bar 1-8)
                Spreads into the bar's 12 buttons in game (`spread`, like a spread submenu; the
                settings preview shows it as one slice). Hidden while the bar has no actions, or
                is turned off in Options > Action Bars (not checked with a bar addon loaded: they
                turn Blizzard's bars off).
    actionslot  bar, button: 1-12
                One button of a spread bar (never saved in a menu, only made by the spread).
                Fires the action slot itself (secure "action" type): whatever is on the bar,
                with its icon, cooldown, state and tooltip. Hidden while the slot is empty.

    Action Bar 1 pages (stance / form, stealth, skyriding, vehicle / possess / override, Shift+1-6):
    a secure state driver keeps the page (`PageFrame`, its "state-page"), and Ring_Secure's release
    points a bar 1 button at that page's slot ("*pagedbutton-<suffix>" holds its button number),
    so it follows the page in combat too. Which buttons the menu has is decided out of combat:
    a page change in combat can leave one empty until combat ends.

    Slots, like Blizzard's bars: bar 1 = page slots ((page - 1) * 12 + button); bar 2 61-72,
    bar 3 49-60, bar 4 25-36, bar 5 37-48, bar 6 145-156, bar 7 157-168, bar 8 169-180.
]]

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local NUM_BARS = 8
local NUM_BUTTONS = 12
local FIRST_SLOT = { 1, 61, 49, 25, 37, 145, 157, 169 } -- bar 1: page 1 (it pages)
local BAR_ADDONS = { "Bartender4", "Dominos", "ElvUI" }  -- they replace Blizzard's bars

-- Action Bar 1's page, by the same rules as the game's main bar (and Bartender's): override /
-- vehicle / possess / temporary shapeshift bars, then a page picked with Shift+1-6, then the bonus
-- bars (stances, forms, stealth; 5 is skyriding).
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
Ring_Kinds.ActionBarPageFrame = PageFrame -- Ring_Secure: bar 1 buttons fire this page's slot

local function GetPage()
    return tonumber(PageFrame:GetAttribute("state-page")) or 1
end

--- The action slot button `button` of `bar` uses right now.
local function GetSlot(bar, button)
    if bar == 1 then return (GetPage() - 1) * NUM_BUTTONS + button end
    return FIRST_SLOT[bar] + button - 1
end

local function IsBarAddonLoaded()
    for _, name in ipairs(BAR_ADDONS) do
        if C_AddOns.IsAddOnLoaded(name) then return true end
    end
    return false
end

--- Whether `bar` is turned on in Options > Action Bars (always, for bar 1 and with a bar addon).
local function IsBarEnabled(bar)
    if bar == 1 or not GetActionBarToggles or IsBarAddonLoaded() then return true end
    -- Bars 2-8 in order; a client that reports fewer bars has no toggle for the rest.
    local toggles = { GetActionBarToggles() }
    if bar - 1 > #toggles then return true end
    return toggles[bar - 1] and true or false
end

local function BarHasActions(bar)
    for button = 1, NUM_BUTTONS do
        if HasAction(GetSlot(bar, button)) then return true end
    end
    return false
end

--- What the slot's cooldown and state follow: its spell or item (a macro: the spell it casts).
local function GetSlotSource(slice)
    local actionType, id, subType = GetActionInfo(GetSlot(slice.bar, slice.button))
    if actionType == "spell" and id then return "spell", id end
    if actionType == "item" and id then return "item", id end
    if actionType == "macro" and id then
        if subType == "spell" then return "spell", id end -- retail reports the macro's spell
        local spellID = GetMacroSpell(id)
        if spellID then return "spell", spellID end
    end
end

local function IsValidBar(bar)
    return type(bar) == "number" and bar >= 1 and bar <= NUM_BARS and bar % 1 == 0
end

Ring_Kinds.Register({
    kind = "actionslot",

    validate = function(slice)
        return IsValidBar(slice.bar) and type(slice.button) == "number" and slice.button >= 1 and slice.button <= NUM_BUTTONS,
            "action slot needs a bar (1-8) and a button (1-12)"
    end,

    apply = function(button, suffix, slice)
        Ring_Kinds.SetAttribute(button, "type", suffix, "action")
        Ring_Kinds.SetAttribute(button, "action", suffix, GetSlot(slice.bar, slice.button))
        -- Bar 1: Ring_Secure points it at the current page's slot when it fires.
        if slice.bar == 1 then Ring_Kinds.SetAttribute(button, "pagedbutton", suffix, slice.button) end
    end,

    icon = function(slice)
        return GetActionTexture(GetSlot(slice.bar, slice.button))
    end,
    label = function(slice)
        local slot = GetSlot(slice.bar, slice.button)
        local actionType, id = GetActionInfo(slot)
        local name
        if actionType == "spell" and id then
            name = C_Spell.GetSpellName(id)
        elseif actionType == "item" and id then
            name = C_Item.GetItemNameByID(id)
        elseif actionType then
            name = GetActionText(slot)
        end
        return name or format(L["Config - Rings - ActionBar - Button"], slice.bar, slice.button)
    end,

    cooldown = GetSlotSource,
    state    = GetSlotSource,

    condition = "actionslot",
    available = function(slice) return HasAction(GetSlot(slice.bar, slice.button)) and true or false end,

    tooltip = function(tooltip, slice)
        local slot = GetSlot(slice.bar, slice.button)
        if not HasAction(slot) then return false end
        tooltip:SetAction(slot)
        return true
    end,
})

Ring_Kinds.Register({
    kind = "actionbar",

    validate = function(slice)
        return IsValidBar(slice.bar), "action bar needs a bar (1-8)"
    end,

    -- In game: the bar's buttons (each hidden while empty, see actionslot).
    spread = function(slice)
        local slices = {}
        for button = 1, NUM_BUTTONS do
            slices[button] = { kind = "actionslot", bar = slice.bar, button = button }
        end
        return slices
    end,

    -- The first action on the bar.
    icon = function(slice)
        for button = 1, NUM_BUTTONS do
            local texture = GetActionTexture(GetSlot(slice.bar, button))
            if texture then return texture end
        end
    end,
    label = function(slice)
        return format(L["Config - Rings - ActionBar - Name"], slice.bar)
    end,

    condition = "actionbar",
    available = function(slice) return IsBarEnabled(slice.bar) and BarHasActions(slice.bar) end,

    search = {
        filter = "misc",
        label  = "actionbar",
        events = { "ACTIONBAR_SLOT_CHANGED" }, -- the icon (the bar's first action)
        -- Every bar, with its slots (bar addons number their bars differently).
        scan   = function(add)
            for bar = 1, NUM_BARS do
                local candidate = add({ kind = "actionbar", bar = bar })
                if candidate then
                    candidate.note = bar == 1 and L["Config - Rings - ActionBar - Note - Paged"]
                        or format(L["Config - Rings - ActionBar - Note - Slots"], FIRST_SLOT[bar], FIRST_SLOT[bar] + NUM_BUTTONS - 1)
                end
            end
        end,
    },
})
