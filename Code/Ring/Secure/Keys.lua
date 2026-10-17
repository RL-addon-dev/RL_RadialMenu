--[[
    Ring_Secure (see Snippets.lua): the menus' keybinds, bound as priority overrides on the
    controller at each rebuild (BindMenuKeys), and taken back when other code binds them.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Crossbar = env.AX_Modules:Import("@\\Ring\\Crossbar")
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")

local InCombatLockdown = InCombatLockdown
local Controller, Helper = Private.Controller, Private.Helper
local pendingBindings = Private.pendingBindings

-- Keys taken back. A menu's keybind is the player's choice, but other code can bind its own
-- priority override on the same key at any time: WoW Forever's gamepad UI re-binds its action bar
-- buttons (on UIParent) whenever its UI changes, and the last binding set wins. Calls to the
-- override binding functions are watched (hooksecurefunc, which doesn't interfere with them);
-- when another owner binds one of the menus' keys, the menu's binding is set again next frame
-- (after combat, if in it). A key taken more than RECLAIM_LIMIT times within RECLAIM_WINDOW
-- seconds is fought over (another addon taking it back too): left alone until the next rebuild.

--- The click a menu's keybind sends: "Gamepad" for a controller button (PAD1, PADRSTICK, ...: a
--- controller's open, with the stick, D-pad, A and B: PRE_CLICK) while WoW Forever's gamepad UI
--- is on, else
--- "LeftButton" (elsewhere a controller button opens like a key: ConsolePort and other controller
--- addons handle the controller their own way). Menus rebuild when the UI switches (Rebuild.lua).
local function GetBindingClick(key)
    local base = key:match("[^%-]+$") or key -- the key without its modifiers (not NUMPAD1)
    return base:sub(1, 3) == "PAD" and env.IsGamepadUI() and "Gamepad" or "LeftButton"
end

local RECLAIM_LIMIT, RECLAIM_WINDOW = 5, 2
local ownedKeys = {}   -- [key] = button name, as Rebuild bound them (the narrowest scope's)
local reclaimCount = {} -- [key] = { count, since }
local givenUp = {}     -- [key] = true: fought over, not taken back until the next rebuild
local reclaimPending = false
local reclaimWaiter = CreateFrame("Frame")

local function ReclaimKeys()
    reclaimPending = false
    if InCombatLockdown() then
        reclaimWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local now = GetTime()
    for key, buttonName in pairs(ownedKeys) do
        if not givenUp[key] and GetBindingAction(key, true) ~= "CLICK " .. buttonName .. ":" .. GetBindingClick(key) then
            local entry = reclaimCount[key]
            if not entry or now - entry.since > RECLAIM_WINDOW then
                entry = { count = 0, since = now }
                reclaimCount[key] = entry
            end
            entry.count = entry.count + 1
            if entry.count > RECLAIM_LIMIT then
                givenUp[key] = true
                env.Print(format("another addon keeps taking %s; the menu stops taking it back until menus change", key))
            else
                SetOverrideBindingClick(Controller, true, key, buttonName, GetBindingClick(key))
            end
        end
    end
end

reclaimWaiter:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ReclaimKeys()
end)

local function OnOverrideBindingSet(owner, _, key)
    if owner == Controller or owner == Helper or not ownedKeys[key] or reclaimPending then return end
    reclaimPending = true
    C_Timer.After(0, ReclaimKeys)
end
for _, name in ipairs({ "SetOverrideBinding", "SetOverrideBindingClick", "SetOverrideBindingSpell",
        "SetOverrideBindingItem", "SetOverrideBindingMacro" }) do
    if _G[name] then hooksecurefunc(name, OnOverrideBindingSet) end
end

-- Stick dispatchers (Snippets.lua, STICK_CLICK): one per stick (L3 / R3), made when a menu first
-- uses it (frames can't be destroyed: reused). The stick is bound to it instead of a menu; it
-- opens the menu of the modifiers held.
local SIDES = { "TOP", "LEFT", "RIGHT", "BOTH" }
local dispatchers = {}

local function GetDispatcher(stick)
    local dispatcher = dispatchers[stick]
    if not dispatcher then
        dispatcher = CreateFrame("Button", "RLRM_Stick_" .. stick, UIParent, "SecureActionButtonTemplate")
        dispatcher:SetSize(1, 1)
        dispatcher:EnableMouse(false)
        dispatcher:RegisterForClicks("AnyDown")
        dispatcher:SetAttribute("useOnKeyDown", true)
        dispatcher:SetAttribute("type", "macro")
        SecureHandlerWrapScript(dispatcher, "OnClick", Controller, Private.STICK_CLICK)
        dispatchers[stick] = dispatcher
    end
    return dispatcher
end

--- Calls callback(binding) for each of SetupRing's keybinds (pendingBindings), widest scope first:
--- where a class or character menu uses the same key, it comes after (and replaces) the other.
local function ForEachBinding(callback)
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        for _, binding in ipairs(pendingBindings) do
            if binding.scope == scope then callback(binding) end
        end
    end
end

--- Binds the keybinds SetupRing collected (pendingBindings), the narrowest scope's menu winning a
--- shared key. L3 / R3 combos (Ring_Crossbar) go to their stick's dispatcher, bound to the stick
--- (in WoW Forever's gamepad UI only). The keys are remembered to take back from other bindings
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
            SetOverrideBindingClick(Controller, true, binding.key, binding.button, GetBindingClick(binding.key))
            ownedKeys[binding.key] = binding.button
        elseif gamepadUI then
            sticks[stick] = sticks[stick] or {}
            sticks[stick][side] = binding.button
        end
    end)

    for stick in pairs(sticks) do GetDispatcher(stick) end
    for stick, dispatcher in pairs(dispatchers) do
        local menus = sticks[stick] or {}
        for _, side in ipairs(SIDES) do dispatcher:SetAttribute("menu-" .. side, menus[side]) end
        if sticks[stick] then
            dispatcher:SetAttribute("modifier-LEFT", Ring_Crossbar.GetModifierIndex("LEFT"))
            dispatcher:SetAttribute("modifier-RIGHT", Ring_Crossbar.GetModifierIndex("RIGHT"))
            SetOverrideBindingClick(Controller, true, stick, dispatcher:GetName(), GetBindingClick(stick))
            ownedKeys[stick] = dispatcher:GetName()
        end
    end
end
