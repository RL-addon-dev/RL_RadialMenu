--[[
    ConsolePort, the controller addon: whether it drives the controller, and the bits of its setup
    the menus use (the game settings it sets, like the buttons it uses as modifiers). They're only
    read here, so the rest of the addon asks Utils_ConsolePort.IsActive and these helpers.

    Forever's gamepad UI has its own controller support (env.IsGamepadUI). The two never overlap,
    and controller input alone (C_GamePad.IsEnabled) is never checked.
]]

local env = select(2, ...)
local Utils_ConsolePort = env.AX_Modules:New("@\\Utils\\ConsolePort")

-- The game's settings that make a controller button act as a modifier, by modifier. ConsolePort
-- sets them (LT is Shift by default).
local EMULATED_MODIFIER_CVARS = {
    SHIFT = "GamePadEmulateShift",
    CTRL  = "GamePadEmulateCtrl",
    ALT   = "GamePadEmulateAlt",
}
-- The game's setting that sends the right stick's directions as keys (PADRSTICKUP...). ConsolePort
-- owns it (its Allow Radial Bindings option), and puts its own value back whenever bindings change.
local STICK_KEYS_CVAR = "GamePadStickAxisButtons"
local POINTED_UNITS = { "softenemy", "softfriend" }
local NO_UNITS = {}

--- Whether ConsolePort drives the controller: it's loaded, controller input is on, and Forever's
--- gamepad UI isn't (that keeps its own controller support).
---@return boolean
function Utils_ConsolePort.IsActive()
    return _G["ConsolePort"] ~= nil and C_GamePad ~= nil and C_GamePad.IsEnabled() and not env.IsGamepadUI()
end

--- The units ConsolePort points at in place of the mouseover (its soft targets, enemy first), or
--- none when it isn't active.
---@return string[]
function Utils_ConsolePort.GetPointedUnits()
    return Utils_ConsolePort.IsActive() and POINTED_UNITS or NO_UNITS
end



-- Claiming keys
--
-- ConsolePort binds the controller's buttons itself, in layers (its ConsolePortLayers frame), and
-- binds them again whenever a modifier is pressed or let go. So a key another addon binds is taken
-- back as soon as LT is let go. Secure code can claim a key in its layers instead: the highest
-- claim on a key is the one bound, and stays bound through those changes. MODAL is the highest,
-- where ConsolePort's own rings claim A and B while they're open.
--
-- SetupClaims gives a secure frame two snippets, run with RunAttribute from its own snippets (which
-- spell out their names, since restricted code can't read Lua constants).
--     "consoleport-claim"    key, target frame name, mouse button: claims `key` to click `target`
--     "consoleport-release"  key, or nothing for every claim: gives them back
-- Without ConsolePort they do nothing.

local LAYERS_FRAME = "ConsolePortLayers"
local CLAIM_OWNER = "RLRM_Menus" -- the name the claims are made under

local CLAIM_SNIPPET = ([[
    local layers = self:GetAttribute("consoleport-active") and self:GetFrameRef("consoleport-layers")
    if not layers then return end
    local key, target, button = ...
    layers:RunAttribute("Claim", %q, "MODAL", key, "click", target, button)
]]):format(CLAIM_OWNER)

local RELEASE_SNIPPET = ([[
    local layers = self:GetAttribute("consoleport-active") and self:GetFrameRef("consoleport-layers")
    if not layers then return end
    local key = ...
    if key then
        layers:RunAttribute("Release", %q, key)
    else
        layers:RunAttribute("ReleaseAll", %q)
    end
]]):format(CLAIM_OWNER, CLAIM_OWNER)

--- Prepares secure frame `frame` (a SecureHandler) for claims, or switches them off without
--- ConsolePort. Claims left over from before are given back. Out of combat.
---@param frame Frame
function Utils_ConsolePort.SetupClaims(frame)
    local layers = _G[LAYERS_FRAME]
    local active = Utils_ConsolePort.IsActive() and layers ~= nil and layers.ReleaseAll ~= nil
    if active then
        SecureHandlerSetFrameRef(frame, "consoleport-layers", layers)
        layers:ReleaseAll(CLAIM_OWNER)
    end
    frame:SetAttribute("consoleport-active", active or nil)
    frame:SetAttribute("consoleport-claim", CLAIM_SNIPPET)
    frame:SetAttribute("consoleport-release", RELEASE_SNIPPET)
end

--- Whether controller button `button` acts as a modifier (Shift, Ctrl or Alt).
---@param button string
---@return boolean
local function IsModifierButton(button)
    for _, cvar in pairs(EMULATED_MODIFIER_CVARS) do
        if GetCVar(cvar) == button then return true end
    end
    return false
end

-- Capturing a keybind: a modifier button pressed with no other button yet. Let go on its own, it's
-- the keybind. Another button pressed while it's held makes it that button's modifier.
local lonelyModifier

--- Starts reading a keybind capture's presses (ReadCapturePress).
function Utils_ConsolePort.StartCapture()
    lonelyModifier = nil
end

--- Reads a controller button's press or release while a keybind is captured. Any button can be
--- bound: it returns the button once the keybind is known, which is any button on its press, and
--- a modifier button (LT) on its release with nothing pressed with it. A stick's directions are
--- never a keybind (walking, and aiming in an open menu, use them), so they're ignored, and so is
--- anything else while it returns nil: keep listening. The caller adds the modifiers held at that
--- moment.
---@param button string
---@param down boolean
---@return string?
function Utils_ConsolePort.ReadCapturePress(button, down)
    if button:match("^PAD[LR]STICK%u") then return nil end -- PADLSTICKUP..., not L3 or R3
    if down then
        if IsModifierButton(button) then
            lonelyModifier = button
            return nil
        end
        lonelyModifier = nil
        return button
    end
    if button == lonelyModifier then
        lonelyModifier = nil
        return button
    end
end

--- Whether the right stick's directions come as keys, which Flick to Select and keeping a pick
--- after the stick is let go need. That's ConsolePort's Allow Radial Bindings option.
---@return boolean
function Utils_ConsolePort.HasStickKeys()
    return GetCVarBool(STICK_KEYS_CVAR) == true
end

--- A modifier's text: the controller button it's on, as the game's icon (LT for SHIFT), or the
--- keyboard modifier's own name when no button emulates it.
---@param modifier string "SHIFT", "CTRL", "ALT" or "META"
---@return string
local function GetModifierText(modifier)
    local cvar = EMULATED_MODIFIER_CVARS[modifier]
    local button = cvar and GetCVar(cvar)
    if button and button ~= "" and button ~= "none" then return GetBindingText(button) end
    return _G[modifier .. "_KEY_TEXT"] or modifier
end

--- A controller key's text like "SHIFT-PAD1" as "LT + A", the way WoW Forever's gamepad UI shows
--- a combo (Menu_Crossbar.GetDisplayText): the modifiers as the buttons they're on, then the
--- button, with the game's own controller icons. Nil when `key` isn't a controller button.
---@param key string
---@return string?
function Utils_ConsolePort.GetKeyText(key)
    -- PAD starts the key or follows a modifier (NUMPAD1 is a keyboard key).
    local modifiers, button = key:match("^(.+)%-(PAD%w+)$")
    if not button then modifiers, button = "", key:match("^PAD%w+$") end
    if not button then return nil end
    local parts = {}
    for modifier in modifiers:gmatch("[^%-]+") do parts[#parts + 1] = GetModifierText(modifier) end
    parts[#parts + 1] = GetBindingText(button)
    return table.concat(parts, " + ")
end
