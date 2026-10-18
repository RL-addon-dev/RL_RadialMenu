--[[
    Ring_Secure (see Snippets.lua): the menus' keybinds. They're bound as priority overrides on the
    controller at each rebuild (BindMenuKeys), and taken back when other code binds them.

    A menu's keybind is the player's choice, but other code can bind its own priority override on
    the same key at any time. WoW Forever's gamepad UI re-binds its action bar buttons (on
    UIParent) whenever its UI changes, and the last binding set wins. So calls to the override
    binding functions are watched (hooksecurefunc, which doesn't interfere with them). When another
    owner binds one of the menus' keys, the menu's binding is set again next frame (after combat,
    if in it). A key taken more than RECLAIM_LIMIT times within RECLAIM_WINDOW seconds is fought
    over (another addon taking it back too), so it's left alone until the next rebuild.
]]

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Crossbar = env.AX_Modules:Import("@\\Ring\\Crossbar")
local Ring_Secure = env.AX_Modules:Import("@\\Ring\\Secure")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")

local RECLAIM_LIMIT, RECLAIM_WINDOW = 5, 2

-- The game's override binding functions, watched for other code binding a menu's key.
local OVERRIDE_BINDING_FUNCTIONS = {
    "SetOverrideBinding", "SetOverrideBindingClick", "SetOverrideBindingSpell",
    "SetOverrideBindingItem", "SetOverrideBindingMacro",
}

local ownedKeys = {}    -- [key] = button name, as BindMenuKeys bound them (the narrowest scope's)
local reclaimCount = {} -- [key] = { count, since }
local givenUp = {}      -- [key] = true when fought over: not taken back until the next rebuild
local reclaimPending = false
local reclaimWaiter = CreateFrame("Frame")

-- Stick dispatchers (Snippets.lua, STICK_CLICK), one per stick (L3, R3), made when a menu first
-- uses it and then reused (frames can't be destroyed). The stick is bound to it instead of a menu,
-- and it opens the menu of the modifiers held.
local dispatchers = {} -- [stick] = Button

--- The click a menu's keybind sends. A controller button (PAD1, PADRSTICK...) sends "Gamepad"
--- while WoW Forever's gamepad UI is on, for a controller's open with the stick, D-pad, A and B
--- (PRE_CLICK). Anything else sends "LeftButton", and so does a controller button elsewhere,
--- where it opens like a key (ConsolePort and other controller addons handle the controller their
--- own way). Menus rebuild when the UI switches (Rebuild.lua).
---@param key string
---@return string
local function GetBindingClick(key)
    if Ring_Crossbar.IsPadButton(key) and env.IsGamepadUI() then return Ring_Secure.Click.Gamepad end
    return Ring_Secure.Click.LeftButton
end

--- Binds `key` to click `buttonName`, as the controller's priority override.
---@param key string
---@param buttonName string
local function BindKey(key, buttonName)
    SetOverrideBindingClick(Private.Controller, true, key, buttonName, GetBindingClick(key))
    ownedKeys[key] = buttonName
end

--- Binds the menus' keys again where other code took them, unless they're fought over.
local function ReclaimKeys()
    reclaimPending = false
    if InCombatLockdown() then
        reclaimWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local now = GetTime()
    for key, buttonName in pairs(ownedKeys) do
        local action = "CLICK " .. buttonName .. ":" .. GetBindingClick(key)
        if not givenUp[key] and GetBindingAction(key, true) ~= action then
            local entry = reclaimCount[key]
            if not entry or now - entry.since > RECLAIM_WINDOW then
                entry = { count = 0, since = now }
                reclaimCount[key] = entry
            end
            entry.count = entry.count + 1
            if entry.count > RECLAIM_LIMIT then
                givenUp[key] = true
                env.Print(format(L["Ring - Keys - FoughtOver"], key))
            else
                SetOverrideBindingClick(Private.Controller, true, key, buttonName, GetBindingClick(key))
            end
        end
    end
end

reclaimWaiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ReclaimKeys()
end)

--- Called after any override binding is set. Another owner binding a menu's key takes it back
--- next frame.
local function OnOverrideBindingSet(owner, _, key)
    if owner == Private.Controller or owner == Private.Helper or not ownedKeys[key] or reclaimPending then return end
    reclaimPending = true
    C_Timer.After(0, ReclaimKeys)
end
for _, name in ipairs(OVERRIDE_BINDING_FUNCTIONS) do
    if _G[name] then hooksecurefunc(name, OnOverrideBindingSet) end
end

--- Stick `stick`'s dispatcher, made on first use.
---@param stick string "PADLSTICK" or "PADRSTICK"
---@return Button
local function GetDispatcher(stick)
    local dispatcher = dispatchers[stick]
    if not dispatcher then
        local name = "RLRM_Stick_" .. stick
        dispatcher = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate") --[[@as Button]]
        dispatcher:SetSize(1, 1)
        dispatcher:EnableMouse(false)
        dispatcher:RegisterForClicks("AnyDown")
        dispatcher:SetAttribute("useOnKeyDown", true)
        dispatcher:SetAttribute("type", "macro")
        SecureHandlerWrapScript(dispatcher, "OnClick", Private.Controller, Private.STICK_CLICK)
        dispatchers[stick] = dispatcher
    end
    return dispatcher
end

--- Calls `callback(binding)` for each of SetupRing's keybinds, widest scope first. Where a class
--- or character menu uses the same key, it comes after (and replaces) the other.
---@param callback fun(binding: PendingBinding)
local function ForEachBinding(callback)
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        for _, binding in ipairs(Private.pendingBindings) do
            if binding.scope == scope then callback(binding) end
        end
    end
end

--- Binds the keybinds SetupRing collected, the narrowest scope's menu winning a shared key. L3 and
--- R3 combos (Ring_Crossbar) go to their stick's dispatcher, which is bound to the stick (in WoW
--- Forever's gamepad UI only). The keys are remembered, to take back from other bindings
--- (ReclaimKeys). Out of combat, after ClearOverrideBindings(Controller).
function Private.BindMenuKeys()
    wipe(ownedKeys)
    wipe(reclaimCount)
    wipe(givenUp)

    local sticks = {} -- [stick] = { [side] = menu button name }
    local gamepadUI = env.IsGamepadUI()
    ForEachBinding(function(binding)
        local side, stick = Ring_Crossbar.ParseStick(binding.key)
        if not side then
            BindKey(binding.key, binding.button)
        elseif gamepadUI then
            sticks[stick] = sticks[stick] or {}
            sticks[stick][side] = binding.button
        end
    end)

    for stick in pairs(sticks) do GetDispatcher(stick) end
    for stick, dispatcher in pairs(dispatchers) do
        local menus = sticks[stick] or {}
        for _, side in ipairs(Ring_Crossbar.SIDE_ORDER) do
            dispatcher:SetAttribute(Ring_Secure.Attribute.Menu .. side, menus[side])
        end
        if sticks[stick] then
            -- The crossbar modifiers' button indexes, which STICK_CLICK reads the held ones by.
            for _, side in ipairs({ Ring_Crossbar.Side.Left, Ring_Crossbar.Side.Right }) do
                dispatcher:SetAttribute(Ring_Secure.Attribute.Modifier .. side, Ring_Crossbar.GetModifierIndex(side))
            end
            BindKey(stick, dispatcher:GetName())
        end
    end
end
