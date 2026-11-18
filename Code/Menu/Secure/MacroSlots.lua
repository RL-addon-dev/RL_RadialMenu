--[[
    Menu_Secure (see Snippets.lua): macro slots, action bar slots holding a menu's macro
    (Menu_Macros). Clicked, the macro opens the menu like Relaxed ("Macro"). The slot's key
    opens it like the menu's own keybind instead: it's bound to the menu's button, so the menu
    gets the key's press and release, and Quick works.

    Blizzard's bars only, by the same slots as ActionBar.lua. Bars 2-8 always show their slots, so
    their keys are bound while the bar is turned on. Action Bar 1 pages (forms, stealth, Shift+1-6),
    so its key is bound only while the bar shows the macro's page. A secure state driver on
    the same page conditions does that, in combat too. A slot of bars 2-5 is also a page of Action
    Bar 1, so it can get both. With a bar addon loaded (Bartender, ElvUI...) no keys are bound. The
    addon's own key presses the macro, which opens the menu like a click.

    The keys are worked out out of combat: at each rebuild, and when the bars, keybinds or macros
    change. A menu's own keybind is left to it (Keys.lua). Menus with a macro get a button even
    without a keybind (Rebuild.lua).

    In the gamepad UI or with ConsolePort, the same macro pressed with the controller opens the
    menu like a controller (Snippets.lua, "menu-padmacro").

    The slot shows the menu's quick action with its cooldown and count, as the wheel's center does
    (Last Used and First Action show what they'd fire). It also shows a small badge in the top-left
    corner (Blizzard's loading spinner) and the macro's name, the menu's. On Blizzard's bars and the
    gamepad UI's crossbar that's drawn over the button, so it follows every change, in combat too.
    The macro's own icon follows it as well, out of combat, for bar addons, where the button can't
    be found.
]]

local env = select(2, ...)
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")
local Menu_Macros = env.AX_Modules:Import("@\\Menu\\Macros")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Actions = env.AX_Modules:Import("@\\Menu\\Actions")
local Menu_Layout = env.AX_Modules:Import("@\\Menu\\Layout")
local Private = env.AX_Modules:Import("@\\Menu\\Secure\\Private")

local NUM_BUTTONS = 12
local LAST_SLOT = 180    -- bar 8's last slot
local PAGED_SLOTS = 132  -- Action Bar 1's pages 1-11 (bonus bars included)
local ALWAYS = 0         -- an entry's page when its key is bound whatever Action Bar 1's page
-- The keybind commands of bars 2-8, by bar (bar 1 is ACTIONBUTTON, by page).
local BAR_COMMANDS = {
    nil, "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON",
}

-- Owns the macro slots' key bindings, kept as attributes set out of combat ("count", "page-<n>",
-- "key-<n>", "button-<n>"). "Apply" binds the ones for Action Bar 1's current page.
local Binder = CreateFrame("Frame", "RLRM_MacroSlotKeys", UIParent, "SecureHandlerStateTemplate")
Binder:SetAttribute("Apply", [[
    local page = tonumber((...)) or 1
    self:ClearBindings()
    for n = 1, self:GetAttribute("count") or 0 do
        local entryPage = self:GetAttribute("page-" .. n)
        if entryPage == 0 or entryPage == page then
            self:SetBindingClick(true, self:GetAttribute("key-" .. n), self:GetAttribute("button-" .. n), "LeftButton")
        end
    end
]])
Binder:SetAttribute("_onstate-page", [[ self:RunAttribute("Apply", newstate) ]])
RegisterStateDriver(Binder, "page", Menu_Kinds.GetActionBarPageConditions())

local lastSignature
local refreshPending = false
local rebuildAsked = {} -- [menuId] = true once its macro asked for a rebuild to make its button
local combatWaiter = CreateFrame("Frame")

--- The keybind commands that press action slot `slot`, each with the Action Bar 1 page it needs
--- (ALWAYS for bars 2-8).
---@param slot integer
---@return { command: string, page: integer }[]
local function GetSlotCommands(slot)
    local commands = {}
    for bar = 2, #BAR_COMMANDS do
        local first = Menu_Kinds.ACTION_BAR_FIRST_SLOT[bar]
        if slot >= first and slot < first + NUM_BUTTONS and Menu_Kinds.IsActionBarEnabled(bar) then
            commands[#commands + 1] = { command = BAR_COMMANDS[bar] .. (slot - first + 1), page = ALWAYS }
        end
    end
    if slot <= PAGED_SLOTS then
        local page, button = math.ceil(slot / NUM_BUTTONS), (slot - 1) % NUM_BUTTONS + 1
        commands[#commands + 1] = { command = "ACTIONBUTTON" .. button, page = page }
    end
    return commands
end

--- The menu whose macro is in action slot `slot`, or nil.
---@param slot integer
---@return string?
local function GetSlotMenuId(slot)
    local actionType, id, subType = GetActionInfo(slot)
    if actionType ~= "macro" or not id or subType == "spell" then return nil end
    return (Menu_Macros.Parse(GetMacroBody(id)))
end

--- Asks for a rebuild when a menu has a macro but no button yet (a new macro for a menu with no
--- keybind), which makes it one. Wherever the macro is placed, the crossbar and bar addons too.
--- Each menu asks once until it has its button, so a menu the rebuild skips can't loop.
local function RequestMissingButtons()
    local missing = false
    for _, menuId in ipairs(Menu_Macros.ListMenuIds()) do
        if Private.menusById[menuId] then
            rebuildAsked[menuId] = nil
        elseif not rebuildAsked[menuId] and Menu_Data.GetMenu(menuId) then
            rebuildAsked[menuId] = true
            missing = true
        end
    end
    if missing then Private.RequestRebuild() end
end

--- Every macro slot key to bind: { page, key, button }.
---@return { page: integer, key: string, button: string }[]
local function CollectEntries()
    local entries = {}
    if Menu_Kinds.IsActionBarAddonLoaded() then return entries end
    for slot = 1, LAST_SLOT do
        local menuId = GetSlotMenuId(slot)
        local button = menuId and Private.menusById[menuId] and Private.buttonsById[menuId]
        if button then
            for _, entry in ipairs(GetSlotCommands(slot)) do
                for _, key in ipairs({ GetBindingKey(entry.command) }) do
                    if not Private.IsMenuKey(key) then
                        entries[#entries + 1] = { page = entry.page, key = key, button = button:GetName() }
                    end
                end
            end
        end
    end
    return entries
end

--- Binds the macro slots' keys, when they changed. Out of combat, else once combat ends.
function Private.RefreshMacroSlotKeys()
    if InCombatLockdown() then
        combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    Private.RequestMacroSlotIcons() -- a rebuild may have changed a quick action
    RequestMissingButtons()
    local entries = CollectEntries()
    local parts = {}
    for _, entry in ipairs(entries) do parts[#parts + 1] = entry.page .. ":" .. entry.key .. ":" .. entry.button end
    local signature = table.concat(parts, ",")
    if signature == lastSignature then return end
    lastSignature = signature

    local previous = Binder:GetAttribute("count") or 0
    for n, entry in ipairs(entries) do
        Binder:SetAttribute("page-" .. n, entry.page)
        Binder:SetAttribute("key-" .. n, entry.key)
        Binder:SetAttribute("button-" .. n, entry.button)
    end
    for n = #entries + 1, previous do
        Binder:SetAttribute("page-" .. n, nil)
        Binder:SetAttribute("key-" .. n, nil)
        Binder:SetAttribute("button-" .. n, nil)
    end
    Binder:SetAttribute("count", #entries)
    SecureHandlerExecute(Binder, [[ self:RunAttribute("Apply", self:GetAttribute("state-page")) ]])
end

--- Refreshes next frame, so a burst of events (a whole bar changing) causes one.
local function RequestRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        Private.RefreshMacroSlotKeys()
    end)
end

combatWaiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    RequestRefresh()
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
watcher:RegisterEvent("UPDATE_BINDINGS")
watcher:RegisterEvent("UPDATE_MACROS")
watcher:SetScript("OnEvent", RequestRefresh)

--- The menu ids with a macro, which get a button even without a keybind.
---@return table<string, true>
function Private.GetMacroMenuIds()
    local ids = {}
    for _, menuId in ipairs(Menu_Macros.ListMenuIds()) do ids[menuId] = true end
    return ids
end



-- Icons

local BUTTON_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}
-- Crossbar buttons have a round and a square mask, and show one.
local ICON_MASK_KEYS = { "IconMask", "CircleMask", "SquareMask" }
local DEFAULT_ICON_SIZE = 45 -- for an icon that isn't laid out yet
-- The crossbar's round buttons swipe their cooldown in this shape.
local ROUND_SWIPE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

---@class BlizzardActionButton : Button
---@field action number? the action slot it shows now
---@field icon Texture?
---@field cooldown Cooldown?
---@field IconMask MaskTexture?
---@field CircleMask MaskTexture? a crossbar button's round shape
---@field SquareMask MaskTexture? a crossbar button's square shape
---@field Name FontString? the macro's name

---@class MacroSlotOverlay
---@field Icon Texture the quick action's icon, over the button's own
---@field Badge MenuBadge the menu badge, in the top-left corner
---@field Cooldown Cooldown
---@field ChargeCooldown Cooldown
---@field Count FontString
---@field action Action? the quick action it shows, for its cooldown

local overlays = {} -- [button] = MacroSlotOverlay
local crossbarButtons = {} -- the gamepad UI's crossbar buttons (BlizzardActionButton)
local iconsPending = false

--- Calls `callback` with each of Blizzard's action buttons, the crossbar's included.
---@param callback fun(button: BlizzardActionButton)
local function ForEachActionButton(callback)
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for number = 1, NUM_BUTTONS do
            local button = _G[prefix .. number]
            if button then callback(button) end
        end
    end
    for _, button in ipairs(crossbarButtons) do callback(button) end
end

--- The overlay of Blizzard action button `button`, made the first time (out of combat).
---@param button BlizzardActionButton
---@return MacroSlotOverlay?
local function GetOverlay(button)
    if overlays[button] then return overlays[button] end
    if InCombatLockdown() then return nil end
    local icon = button:CreateTexture(nil, "ARTWORK", nil, 7)
    icon:SetAllPoints(button.icon or button)
    for _, key in ipairs(ICON_MASK_KEYS) do
        if button[key] then icon:AddMaskTexture(button[key]) end
    end
    local iconRegion = button.icon or button
    local iconSize = iconRegion:GetWidth()
    -- Like the wheel's cooldowns (CreateActionIcon), over the button's own, which never runs.
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate") --[[@as Cooldown]]
    cooldown:SetAllPoints(button.cooldown or iconRegion)
    cooldown:SetDrawBling(false)
    if button.CircleMask and button.CircleMask:IsShown() then
        ---@diagnostic disable-next-line: missing-parameter texture only, like Blizzard's crossbar
        cooldown:SetSwipeTexture(ROUND_SWIPE)
    end
    local chargeCooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate") --[[@as Cooldown]]
    chargeCooldown:SetAllPoints(cooldown)
    chargeCooldown:SetDrawSwipe(false)
    chargeCooldown:SetDrawEdge(true)
    chargeCooldown:SetDrawBling(false)
    chargeCooldown:SetHideCountdownNumbers(true)
    -- The count and badge, above the cooldowns.
    local top = CreateFrame("Frame", nil, button) --[[@as Frame]]
    top:SetAllPoints(iconRegion)
    top:SetFrameLevel(chargeCooldown:GetFrameLevel() + 2)
    local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    local badge = Menu_Layout.CreateMenuBadge(top, iconRegion, iconSize > 0 and iconSize or DEFAULT_ICON_SIZE)
    icon:Hide()
    overlays[button] = {
        Icon           = icon,
        Badge          = badge,
        Cooldown       = cooldown,
        ChargeCooldown = chargeCooldown,
        Count          = count,
    }
    return overlays[button]
end

--- The icon of menu `menuId`'s quick action, which its macro slots show. Nil without one.
---@param menuId string
---@return number|string?
local function GetQuickIcon(menuId)
    local action = Private.GetQuickShownAction(menuId)
    return action and Menu_Actions.GetIcon(action)
end

--- Refreshes the cooldowns and counts on the overlays (Menu_Layout.COOLDOWN_EVENTS).
local function UpdateOverlayCooldowns()
    for _, overlay in pairs(overlays) do
        -- It reads only Cooldown, ChargeCooldown and Count.
        Menu_Layout.UpdateIconCooldown(overlay --[[@as ActionIcon]], overlay.action)
    end
end

--- The macros' own icons follow their menu's quick action, for bars whose buttons aren't drawn
--- over. Only file ids are written, because the game may report a path back as another value,
--- which would edit it again every refresh. Out of combat.
local function UpdateMacroIcons()
    if InCombatLockdown() then return end
    for _, menuId in ipairs(Menu_Macros.ListMenuIds()) do
        local index = Menu_Macros.Find(menuId)
        local icon = GetQuickIcon(menuId)
        if index and type(icon) == "number" then
            local name, current, body = GetMacroInfo(index)
            if name and icon ~= current then EditMacro(index, name, icon, body) end
        end
    end
end

--- Shows each Blizzard button's overlay while its slot holds a menu's macro, and hides it otherwise.
function Private.RefreshMacroSlotIcons()
    ForEachActionButton(function(button)
        local slot = button.action
        local menuId = type(slot) == "number" and GetSlotMenuId(slot)
        local overlay = (menuId and GetOverlay(button)) or overlays[button]
        if not overlay then return end
        overlay.action = menuId and Private.GetQuickShownAction(menuId) or nil
        local icon = overlay.action and Menu_Actions.GetIcon(overlay.action)
        if icon then Menu_Layout.SetIcon(overlay.Icon, icon) end
        overlay.Icon:SetShown(icon ~= nil)
        overlay.Badge:SetShown(menuId and true or false)
    end)
    UpdateOverlayCooldowns()
    UpdateMacroIcons()
end

--- Refreshes the icons next frame (a pick, a scroll, a page change).
function Private.RequestMacroSlotIcons()
    if iconsPending then return end
    iconsPending = true
    C_Timer.After(0, function()
        iconsPending = false
        Private.RefreshMacroSlotIcons()
    end)
end

local iconWatcher = CreateFrame("Frame")
iconWatcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
iconWatcher:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
iconWatcher:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
iconWatcher:RegisterEvent("PLAYER_REGEN_ENABLED") -- overlays and macro icons skipped in combat
iconWatcher:SetScript("OnEvent", Private.RequestMacroSlotIcons)

local cooldownWatcher = CreateFrame("Frame")
for _, event in ipairs(Menu_Layout.COOLDOWN_EVENTS) do cooldownWatcher:RegisterEvent(event) end
cooldownWatcher:SetScript("OnEvent", UpdateOverlayCooldowns)

-- Forever's crossbar pages without the events above, so its buttons' UpdateAction is hooked.
EventUtil.ContinueOnAddOnLoaded("Blizzard_GamepadActionBars", function()
    local frame = _G["GamepadMainActionBarFrame"]
    if not (frame and frame.GetActionBars) then return end
    for _, bar in pairs(frame:GetActionBars()) do
        for _, button in ipairs(bar.actionButtons or {}) do
            -- The possess bar's pet buttons have none, and never hold a macro.
            if type(button.UpdateAction) == "function" then
                crossbarButtons[#crossbarButtons + 1] = button
                hooksecurefunc(button, "UpdateAction", Private.RequestMacroSlotIcons)
            end
        end
    end
    Private.RequestMacroSlotIcons()
end)
