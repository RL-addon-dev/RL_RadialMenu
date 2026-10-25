--[[
    Menu_Stick: a controller's right stick, for the in-game menu a controller opened (Menu_View, in
    WoW Forever's gamepad UI).
        - Its direction while tilted, picking like the secure snippet does (the same stick and
          threshold as Menu_Secure).
        - Keeping it from turning the camera while the menu is shown.
]]

local env = select(2, ...)
local Menu_Stick = env.AX_Modules:New("@\\Menu\\Stick")

-- The right stick (stick 2 of the mapped state) picks once tilted this far, like the secure snippet.
local STICK, STICK_MIN = 2, 0.5
local IsGamePadEnabled = C_GamePad and C_GamePad.IsEnabled
local GetGamePadState = C_GamePad and C_GamePad.GetDeviceMappedState

--- The right stick's direction (up is +y), or nil while it's not tilted or there's no controller.
---@return number? x
---@return number? y
function Menu_Stick.GetTilted()
    if not (IsGamePadEnabled and IsGamePadEnabled()) then return nil end
    local state = GetGamePadState()
    local stick = state and state.sticks and state.sticks[STICK]
    if stick and stick.len >= STICK_MIN then return stick.x, stick.y end
end

-- Keeping the right stick from turning the camera, while the left stick still walks.
--
-- The problem is that a frame that takes stick input takes both sticks or neither. Its handler's
-- return value is ignored, and only its propagate flag (SetPropagateKeyboardInput) decides.
--
-- The trick is ConsolePort's (by Sebastian Lindfors, Artistic License 2.0, in its
-- Controller\Radial.lua). Every frame, the game sends stick events in a fixed order.
--   1. The raw events: Left, Right, Gyro.
--   2. Their twins, which the game acts on: Movement, Camera, Look. A twin is only sent if its raw
--      event was.
-- Two frames use that order.
--   - The watcher passes everything through. When it sees Right move, it shows the blocker. That's
--     right away if Left didn't send this frame (no Movement twin coming), else once the Movement
--     twin has gone through, so walking isn't blocked.
--   - The blocker passes nothing. It swallows the Camera twin, then hides.
-- Each frame starts clean, as the watcher's OnUpdate hides the blocker. Show and hide work in
-- combat, and the propagate flags are set once, out of combat.
local StickWatcher = CreateFrame("Frame")
local StickBlocker = CreateFrame("Frame")
local CAN_BLOCK = StickWatcher.EnableGamePadStick ~= nil
local leftSent  -- the left stick sent its raw event this frame, so its twin comes before Camera
local showAfter -- the twin to let through before the blocker shows

if CAN_BLOCK then
    StickWatcher:SetFrameStrata("BACKGROUND")
    StickBlocker:SetFrameStrata("TOOLTIP")

    StickWatcher:SetScript("OnGamePadStick", function(_, stick, _, _, len)
        if stick == showAfter then
            showAfter = nil
            StickBlocker:Show()
        elseif stick == "Left" then
            leftSent = true
        elseif stick == "Right" and len and len > 0 then
            if leftSent then showAfter = "Movement" else StickBlocker:Show() end
        end
    end)
    StickBlocker:SetScript("OnGamePadStick", function(self, stick)
        if stick == "Camera" then self:Hide() end
    end)
    -- Every frame, after the stick events, start clean.
    StickWatcher:SetScript("OnUpdate", function()
        leftSent, showAfter = nil, nil
        StickBlocker:Hide()
    end)

    -- Setting a handler switches stick input on. The watcher only listens (and runs its OnUpdate)
    -- while a menu is shown, and the blocker listens whenever it's shown.
    StickWatcher:EnableGamePadStick(false)
    StickWatcher:Hide()
    StickBlocker:EnableGamePadStick(true)
    StickBlocker:Hide()

    local function SetPropagation()
        StickWatcher:SetPropagateKeyboardInput(true)
        StickBlocker:SetPropagateKeyboardInput(false)
    end
    if InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            SetPropagation()
        end)
    else
        SetPropagation()
    end
end

--- While on (a menu is shown), the right stick doesn't turn the camera, and the left stick still
--- walks.
---@param on boolean
function Menu_Stick.SetCameraBlocked(on)
    if not CAN_BLOCK then return end
    if on and not (IsGamePadEnabled and IsGamePadEnabled()) then return end
    StickWatcher:SetShown(on)
    StickWatcher:EnableGamePadStick(on)
    if not on then StickBlocker:Hide() end
end
