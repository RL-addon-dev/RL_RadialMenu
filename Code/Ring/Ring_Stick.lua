--[[
    A controller's right stick, for the in-game menu opened by a controller (Ring_View; WoW Forever's
    gamepad UI): its direction while tilted, picking like the secure snippet does (Ring_Secure: same
    stick and threshold), and keeping it from turning the camera while the menu is shown.
]]

local env = select(2, ...)
local Ring_Stick = env.AX_Modules:New("@\\Ring\\Stick")

-- The right stick (stick 2 of the mapped state) picks once tilted this far, like the secure snippet.
local STICK, STICK_MIN = 2, 0.5
local IsGamePadEnabled = C_GamePad and C_GamePad.IsEnabled
local GetGamePadState = C_GamePad and C_GamePad.GetDeviceMappedState

--- The right stick's direction (x, y; up is +y), or nil while it's not tilted (or no controller).
function Ring_Stick.GetTilted()
    if not (IsGamePadEnabled and IsGamePadEnabled()) then return nil end
    local state = GetGamePadState()
    local stick = state and state.sticks and state.sticks[STICK]
    if stick and stick.len >= STICK_MIN then return stick.x, stick.y end
end

-- Keeping the right stick from turning the camera, while the left stick still walks.
--
-- The problem: a frame that takes stick input takes both sticks or neither. Its handler's return
-- value is ignored; only its propagate flag (SetPropagateKeyboardInput) decides.
--
-- The trick (ConsolePort's, by Sebastian Lindfors, Artistic License 2.0: its Controller\Radial.lua).
-- Every frame, the game sends stick events in a fixed order:
--   1. raw events:  Left, Right, Gyro
--   2. their twins: Movement, Camera, Look (the ones the game acts on; a twin is only sent if its
--                   raw event was)
-- Two frames use that order:
--   watcher  passes everything through. When it sees Right move, it shows the blocker: right away
--            if Left didn't send this frame (no Movement twin coming), else once the Movement twin
--            has gone through (walking isn't blocked).
--   blocker  passes nothing. It swallows the Camera twin, then hides.
-- Each frame starts clean (the watcher's OnUpdate hides the blocker). Show and hide work in
-- combat; the propagate flags are set once, out of combat.
local StickWatcher = CreateFrame("Frame")
local StickBlocker = CreateFrame("Frame")
local CAN_BLOCK = StickWatcher.EnableGamePadStick ~= nil
local leftSent     -- the left stick sent its raw event this frame: its twin comes before Camera
local showAfter    -- twin to let through before the blocker shows

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
    -- Every frame, after the stick events: start clean.
    StickWatcher:SetScript("OnUpdate", function()
        leftSent, showAfter = nil, nil
        StickBlocker:Hide()
    end)

    -- Setting a handler switches stick input on: the watcher only listens while a menu is shown
    -- (and only runs its OnUpdate then); the blocker listens whenever it's shown.
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

--- While on (a menu is shown), the right stick doesn't turn the camera; the left stick still walks.
function Ring_Stick.SetCameraBlocked(on)
    if not CAN_BLOCK then return end
    if on and not (IsGamePadEnabled and IsGamePadEnabled()) then return end
    StickWatcher:SetShown(on)
    StickWatcher:EnableGamePadStick(on)
    if not on then StickBlocker:Hide() end
end
