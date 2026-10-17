--[[
    Key capture for the Menus tab Keybind row.

    StartCapture(onKey, onCancel) grabs the keyboard, mouse and controller until a key or button
    is pressed:
        a key (with modifiers)           onKey("ALT-CTRL-SHIFT-KEY" in WoW binding order)
        mouse button 3 and up (same)     onKey("SHIFT-BUTTON4", ...)
        a controller button              only while WoW Forever's gamepad UI is on
                                         (env.IsGamepadUI): Ring_Crossbar.FromPress decides,
                                         onKey("PAD:LEFT:PAD1") for a combo (LT + A, D-pad up,
                                         LT + R3 ...), onKey("PADBACK") for another button;
                                         LT / RT / LB / RB alone keep listening, refusals are
                                         said in chat
        Escape, left or right click      onCancel() (plain and modified left / right clicks are
                                         what the rest of the UI runs on: never a keybind)
        modifiers alone                  ignored, keep listening
    Not available in combat (keyboard propagation is protected).
]]

local env = select(2, ...)
local L = env.L
local Ring_Crossbar = env.AX_Modules:Await("@\\Ring\\Crossbar")
local Rings_Keybind = env.AX_Modules:New("@\\Setting\\Rings\\Keybind")

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true
}

-- Covers the screen while listening, so a mouse press anywhere is caught (and doesn't click
-- through to what's under it).
local capture = CreateFrame("Frame", nil, UIParent)
capture:SetFrameStrata("TOOLTIP")
capture:SetAllPoints(UIParent)
capture:Hide()

-- Mouse buttons as WoW binding keys; buttons past 5 follow the same pattern (Button6 = BUTTON6).
local MOUSE_BUTTONS = { MiddleButton = "BUTTON3" }
local CANCEL_BUTTONS = { LeftButton = true, RightButton = true }

-- Controller buttons held while capturing (our frame takes them): Ring_Crossbar.FromPress reads
-- the modifiers held from these.
local HAS_GAMEPAD = capture.EnableGamePadButton ~= nil
local heldButtons = {} -- [button] = true while held (capturing)

local onKey, onCancel

local function Stop()
    capture:Hide()
    capture:EnableKeyboard(false)
    capture:EnableMouse(false)
    if HAS_GAMEPAD then capture:EnableGamePadButton(false) end
    wipe(heldButtons)
    onKey, onCancel = nil, nil
end

--- Binding string for `key` with the modifiers currently held (ALT-CTRL-SHIFT order, like WoW).
function Rings_Keybind.BuildKey(key)
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then prefix = prefix .. "META-" end
    return prefix .. key
end

-- Combat starting while listening: stop, so the next key press reaches its ability.
capture:RegisterEvent("PLAYER_REGEN_DISABLED")
capture:SetScript("OnEvent", function() Rings_Keybind.CancelCapture() end)

capture:SetScript("OnKeyDown", function(_, key)
    if MODIFIER_KEYS[key] then return end

    local keyCallback, cancelCallback = onKey, onCancel
    local binding = Rings_Keybind.BuildKey(key)
    Stop()
    if key == "ESCAPE" then
        if cancelCallback then cancelCallback() end
    elseif keyCallback then
        keyCallback(binding)
    end
end)

capture:SetScript("OnMouseDown", function(_, button)
    local keyCallback, cancelCallback = onKey, onCancel
    local number = button and button:match("^Button(%d+)$")
    local key = MOUSE_BUTTONS[button] or (number and "BUTTON" .. number)
    local binding = key and Rings_Keybind.BuildKey(key) -- before Stop, like OnKeyDown
    Stop()
    if CANCEL_BUTTONS[button] or not key then
        if cancelCallback then cancelCallback() end
    elseif keyCallback then
        keyCallback(binding)
    end
end)

if HAS_GAMEPAD then
    capture:SetScript("OnGamePadButtonDown", function(_, button)
        if not env.IsGamepadUI() then return end -- controller buttons only with controller support
        heldButtons[button] = true
        local key, problem = Ring_Crossbar.FromPress(button, heldButtons)
        if problem then
            if problem ~= "Held" then env.Print(L["Config - Rings - Keybind - Crossbar - " .. problem]) end
            return
        end

        local keyCallback = onKey
        Stop()
        if keyCallback then keyCallback(key) end
    end)
    capture:SetScript("OnGamePadButtonUp", function(_, button)
        heldButtons[button] = nil
    end)
    -- Setting the handlers switches controller button input on: off until a capture wants it.
    capture:EnableGamePadButton(false)
end

--- @return boolean started false in combat
function Rings_Keybind.StartCapture(keyCallback, cancelCallback)
    if InCombatLockdown() then return false end

    onKey, onCancel = keyCallback, cancelCallback
    capture:Show()
    capture:EnableKeyboard(true)
    capture:EnableMouse(true)
    if HAS_GAMEPAD and env.IsGamepadUI() then capture:EnableGamePadButton(true) end
    capture:SetPropagateKeyboardInput(false) -- keep the key from also triggering its binding
    return true
end

function Rings_Keybind.CancelCapture()
    if not capture:IsShown() then return end
    local cancelCallback = onCancel
    Stop()
    if cancelCallback then cancelCallback() end
end

function Rings_Keybind.IsCapturing()
    return capture:IsShown()
end

--- Readable name of the Blizzard keybinding action on `key`, or nil. Ignores override bindings
--- (the rings' own bindings are overrides).
function Rings_Keybind.GetBlizzardConflict(key)
    local action = GetBindingAction(key, false)
    if not action or action == "" then return nil end
    return _G["BINDING_NAME_" .. action] or action
end

-- Controller buttons show as icons in key text (WoW Forever's gamepad UI: inline atlas "|A:...|a"
-- or texture "|T...|t" markup), drawn at ICON_SCALE of their size so they sit with the text. A
-- size of 0 means "the text's height": ICON_TEXT_HEIGHT stands in for it.
local ICON_SCALE = 0.8
local ICON_TEXT_HEIGHT = 12

local function ScaleIconSize(size)
    size = tonumber(size) or 0
    if size == 0 then size = ICON_TEXT_HEIGHT end
    return math.floor(size * ICON_SCALE + 0.5)
end

--- `text` with its inline icons scaled (height, and width when given).
local function ShrinkIcons(text)
    text = text:gsub("|A:([^:|]+):(%-?%d+):(%-?%d+)", function(atlas, height, width)
        return "|A:" .. atlas .. ":" .. ScaleIconSize(height) .. ":" .. ScaleIconSize(width)
    end)
    text = text:gsub("|T([^:|]+):(%-?%d+)(:?)(%-?%d*)", function(path, height, colon, width)
        local scaled = "|T" .. path .. ":" .. ScaleIconSize(height)
        if colon ~= "" then scaled = scaled .. ":" .. (width ~= "" and ScaleIconSize(width) or "") end
        return scaled
    end)
    return text
end

--- Localized, readable key text ("Alt-Space" rather than "ALT-SPACE") where the client has one.
--- Mouse buttons are shortened ("Shift-Mouse 4" rather than "Shift-Mouse Button 4"); controller
--- button icons drawn a little smaller (ShrinkIcons).
function Rings_Keybind.GetDisplayText(key)
    -- Controller combos aren't keys: their buttons' text (Ring_Crossbar).
    if Ring_Crossbar.IsCombo(key) then
        return ShrinkIcons(Ring_Crossbar.GetDisplayText(key))
    end
    local text = GetBindingText and GetBindingText(key)
    if not text or text == "" then return key end

    local number = key:match("BUTTON(%d+)$")
    local long = number and GetBindingText("BUTTON" .. number)
    local at = long and long ~= "" and text:find(long, 1, true)
    if at then
        text = text:sub(1, at - 1) .. format(env.L["Config - Rings - Keybind - Mouse"], number) .. text:sub(at + #long)
    end
    return ShrinkIcons(text)
end
