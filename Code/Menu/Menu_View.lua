--[[
    Menu_View: the in-game menu you see. It's a Menu_Layout wheel, with the open and close
    animation and the live highlight. It's insecure, and only shows what the secure side does.

    The secure controller drives it (Menu_Secure, through CallMethod). Every frame it repeats the
    secure pick's math, so the highlight matches what the release fires (or in Relaxed, once the
    keybind is released, what a left click fires). In a menu a controller opened (WoW Forever's
    gamepad UI), the right stick, tilted, picks over the cursor as the secure snippet does, and it
    doesn't turn the camera while the menu is shown (both through Menu_Stick).
]]

local env = select(2, ...)
local Config = env.Config
local Menu_Actions = env.AX_Modules:Import("@\\Menu\\Actions")
local Menu_Display = env.AX_Modules:Import("@\\Menu\\Display")
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Layout = env.AX_Modules:Import("@\\Menu\\Layout")
local Menu_Stick = env.AX_Modules:Import("@\\Menu\\Stick")
local Menu_View = env.AX_Modules:New("@\\Menu\\View")
local Menu_Secure = env.AX_Modules:Await("@\\Menu\\Secure")

local GetCursorPosition, GetTime = GetCursorPosition, GetTime
local atan2, min, max = math.atan2, math.min, math.max

-- Blizzard's values (the large wheel).
local INTRO_DURATION = 0.2
local OUTRO_DURATION = 0.13
local ANIM_DISTANCE  = 20

-- Icon states (resources, range, active). Range has no event of its own, so all of them are
-- refreshed this often while open. Blizzard's action bars check range on the same interval.
local STATE_INTERVAL = TOOLTIP_UPDATE_TIME or 0.2

-- The right stick's direction (0 to 1) becomes a cursor offset in pixels, for the same wedge math
-- as the mouse (Menu_Layout.GetWedgeIndex). Only its angle should count, so the offset must land
-- outside the dead zone even at the smallest tilt that aims. That's the largest Distance to Select
-- over that tilt, with plenty to spare.
local MIN_AIM_TILT = 0.5    -- the secure snippets' "stick.len >= 0.5"
local STICK_REACH_MARGIN = 10
local STICK_REACH = Config.DEADZONE_MAX / MIN_AIM_TILT * STICK_REACH_MARGIN

-- The tooltip index of the center's quick action (SetActionTooltip), besides wedge indexes.
local QUICK_TOOLTIP = "quick"

---@param value number
---@return number
local function Clamp01(value) return min(max(value, 0), 1) end

--- Blizzard's ease in and out, for progress `p` from 0 to 1.
---@param p number
---@return number
local function InOutCubic(p)
    if p < 0.5 then return 4 * p * p * p end
    local f = -2 * p + 2
    return 1 - f * f * f / 2
end

-- With a fixed position, an optional outline of the gesture at the key down spot (Menu_CursorGuide).
local Guide = env.AX_Modules:Import("@\\Menu\\CursorGuide").Frame

--- The in-game menu's wheel, with what the open menu needs every frame.
---@class MenuView : MenuWheel
---@field menu LiveMenu the open menu
---@field padButton Frame? the menu's secure button, when a controller opened it
---@field probe Frame the secure center probe (read only here)
---@field startX number the cursor at key down, in UIParent units
---@field startY number
---@field originX number where angles are measured from (the key down spot, or the fixed center)
---@field originY number
---@field fromMenu boolean Select From = Menu Center
---@field deadzone number
---@field openTime number
---@field revealDelay number
---@field revealStart number? when the reveal started (nil before the reveal delay passed)
---@field closing boolean
---@field closeStart number
---@field animatedOffset number
---@field nextStateUpdate number?
---@field showTooltips boolean
---@field tooltipIndex integer|string|nil what the tooltip shows (a wedge index or QUICK_TOOLTIP)
---@field useGuide boolean

local View = Menu_Layout.CreateWheel(UIParent, "RLRM_MenuView") --[[@as MenuView]]
View:SetFrameStrata("FULLSCREEN_DIALOG")
View:SetShowStates(true)
View:Hide()

-- While shown, a controller's right stick aims instead of turning the camera (Menu_Stick).
View:HookScript("OnHide", function() Menu_Stick.SetCameraBlocked(false) end)

--- What the center shows: the quick action (or a lone action) until the cursor has left it, and
--- the cancel ring's highlight while the cursor is inside the dead zone.
---@param self MenuView
---@param inDeadzone boolean
---@param moved boolean the cursor left the center probe
local function UpdateCenter(self, inDeadzone, moved)
    if self.isSingleCentered then
        -- The lone action fires unless the cursor left the center and came back (a cancel).
        local cancel = moved and inDeadzone
        self:SetCenter(not cancel, true)
        return
    end
    self:SetCenter(not moved and self.quickAction ~= nil, inDeadzone)
end

--- Steps the reveal (after the reveal delay) or the close animation, a fade plus the icons
--- sliding out.
---@param self MenuView
---@param now number
---@return boolean alive false once the close animation has finished and the view is hidden
local function UpdateAnimation(self, now)
    local offset = 0
    if self.closing then
        local p = Clamp01((now - self.closeStart) / OUTRO_DURATION)
        self:SetAlpha(1 - p)
        offset = -ANIM_DISTANCE * InOutCubic(p)
        if p >= 1 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return false
        end
    elseif self.revealStart then
        local p = Clamp01((now - self.revealStart) / INTRO_DURATION)
        self:SetAlpha(p)
        offset = -ANIM_DISTANCE * (1 - InOutCubic(p))
        if p >= 1 and self.animatedOffset == 0 then return true end
    else
        return true
    end

    if offset ~= self.animatedOffset then
        self.animatedOffset = offset
        self:PositionIcons(offset)
    end
    return true
end

--- With Show Action Tooltips, the tooltip of what a release would fire, at the HUD Tooltip
--- position (Edit Mode), like an action button's. It's shown again only when it changes.
---@param self MenuView
---@param index integer|string|nil a wedge index, QUICK_TOOLTIP (the center's quick action), or nil
---     to hide it
local function SetActionTooltip(self, index)
    if index == self.tooltipIndex then return end
    self.tooltipIndex = index
    local action = index and self.showTooltips and (index == QUICK_TOOLTIP and self.quickAction or self.actions[index])
    if not action then
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        return
    end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    end
    if not Menu_Actions.SetTooltip(GameTooltip, action) then
        GameTooltip:SetText(Menu_Actions.GetLabel(action), 1, 1, 1) -- nothing richer than a name
    end
    GameTooltip:Show()
end

--- Every frame while open: the animation, then the highlight, pointer and center for the cursor.
---@param self MenuView
local function OnUpdate(self)
    local now = GetTime()
    if not self.revealStart and not self.closing and now - self.openTime >= self.revealDelay then
        self.revealStart = now
    end
    local alive = UpdateAnimation(self, now)
    if alive and not self.closing and now >= (self.nextStateUpdate or 0) then
        self.nextStateUpdate = now + STATE_INTERVAL
        self:UpdateStates()
    end
    if self.useGuide then
        if alive then Guide:SetAlpha(self:GetAlpha()) else Guide:Hide() end
    end
    if not alive or self.closing then return end

    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local dx, dy = x / scale - self.originX, y / scale - self.originY
    local moved = not self.probe:IsShown()
    -- The right stick, tilted, counts as the cursor far out in its direction. In a menu a
    -- controller opened, the cursor doesn't count, and the stick let go shows the pick it left
    -- (Menu_Secure.Attribute.Sticky on the menu's button), else the center (the quick action).
    local stickX, stickY
    if self.padButton then stickX, stickY = Menu_Stick.GetTilted() end
    if stickX then
        dx, dy, moved = stickX * STICK_REACH, stickY * STICK_REACH, true
    elseif self.padButton then
        local sticky = self.padButton:GetAttribute(Menu_Secure.Attribute.Sticky)
        if sticky then
            local angle = Menu_Layout.GetWedgeAngle(sticky, #self.menu.actions)
            dx, dy, moved = math.cos(angle) * STICK_REACH, math.sin(angle) * STICK_REACH, true
        else
            dx, dy, moved = 0, 0, false
        end
    end

    -- The same rules as the secure snippet (Menu_Secure). With Select From = Menu Center, nothing
    -- is picked until the cursor leaves the quick action square, wherever it is over the menu. In
    -- Relaxed, a click picks by the same rules.
    local index
    if not (self.fromMenu and not moved) then
        index = Menu_Layout.GetWedgeIndex(dx, dy, #self.menu.actions, self.deadzone)
    end
    self:SetSelection(index)
    -- What a release (or a Relaxed click) would fire: the highlighted wedge, else the center (the
    -- quick action, or a lone action) until the cursor has left it. It's not shown before the menu
    -- is revealed, so a tap never shows one.
    local tooltip = index
    if not index and not moved then
        tooltip = self.isSingleCentered and 1 or (self.quickAction and QUICK_TOOLTIP) or nil
    end
    SetActionTooltip(self, self.revealStart and tooltip or nil)
    self:SetPointerAngle(index and atan2(dy, dx) or nil)
    if self.useGuide then Guide:Update(index, index and atan2(dy, dx) or nil, moved) end
    UpdateCenter(self, index == nil, moved)
end



--- Opens the menu, called by the secure controller when a menu's key is pressed.
---@param menu LiveMenu
---@param startX number the cursor at key down, in UIParent units
---@param startY number
---@param probe Frame the secure center probe (read only here)
---@param quickAction Action? what the quick action would fire
---@param displayActions Action[]? what each wedge shows (a scroll submenu shows its current action),
---     menu.actions by default
---@param relaxed boolean this open works like Relaxed, so it's shown at once (no tap to wait for)
---@param padButton Frame|false the menu's secure button when a controller opened it (its sticky
---     pick shows), so the stick picks and the cursor doesn't
function Menu_View:Open(menu, startX, startY, probe, quickAction, displayActions, relaxed, padButton)
    View.menu = menu
    View.padButton = padButton or nil
    Menu_Stick.SetCameraBlocked(View.padButton ~= nil)
    View.startX, View.startY = startX, startY
    View.probe = probe
    View.quickAction = quickAction
    View.openTime = GetTime()
    View.revealDelay = relaxed and 0 or Menu_Data.GetRevealDelay()
    View.deadzone = Menu_Data.GetDeadzone()
    View.revealStart = nil
    View.closing = false
    View.nextStateUpdate = nil
    View.animatedOffset = -ANIM_DISTANCE

    View:SetShowLabels(Config.Get(Config.Key.ShowActionNames))
    View.showTooltips = Config.Get(Config.Key.ShowActionTooltips) and true or false
    -- Opened again without closing (another menu's key pressed while one is held), so its tooltip goes.
    if GameTooltip:GetOwner() == View then GameTooltip:Hide() end
    View.tooltipIndex = nil
    View:SetActions(displayActions or menu.actions, View.animatedOffset, menu.quickAction ~= nil)
    View:SetScrollBadges(menu.actions, true, View.padButton ~= nil)
    View:SetQuickIcon(quickAction and Menu_Actions.GetIcon(quickAction), quickAction)
    View:SetPointerAngle(nil)
    UpdateCenter(View, true, false)

    -- The position and size are visual only, and the pick stays relative to startX and startY.
    -- SetPoint offsets are in the view's own (scaled) units.
    local scale = Menu_Display.GetScale()
    local centerX, centerY = Menu_Display.GetCenter(startX, startY)
    View:SetScale(scale)
    View:ClearAllPoints()
    View:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX / scale, centerY / scale)
    View:SetAlpha(0)

    -- Where angles are measured from: the key-down cursor spot, or the fixed menu's center with
    -- Select From = Menu Center (the secure snippet uses the same center, see Menu_Secure).
    View.originX, View.originY = startX, startY
    local fixedX, fixedY = Menu_Display.GetFixedCenter()
    View.fromMenu = Menu_Display.IsSelectFromMenu() and fixedX ~= nil
    if View.fromMenu then View.originX, View.originY = fixedX, fixedY end

    -- With a fixed position, an optional guide at the key down spot (UIParent units, like startX
    -- and startY). Not with Select From = Menu Center, where you point at the menu itself.
    View.useGuide = Menu_Display.IsFixed() and not View.fromMenu
        and Config.Get(Config.Key.CursorGuide) and true or false
    if View.useGuide then
        Guide:Setup(#menu.actions, View.deadzone, Menu_Data.GetProbeSize(), View.quickAction ~= nil)
        Guide:ClearAllPoints()
        Guide:SetPoint("CENTER", UIParent, "BOTTOMLEFT", startX, startY)
        Guide:SetAlpha(0)
        Guide:Show()
    else
        Guide:Hide()
    end

    View:SetScript("OnUpdate", OnUpdate)
    View:Show()
    OnUpdate(View)
end

--- Updates one wedge's icon while the menu is open (a scroll submenu was scrolled).
---@param index integer
---@param action Action
function Menu_View:SetWedgeIcon(index, action)
    if not View:IsShown() then return end
    View:SetWedgeAction(index, action)
    -- The highlighted wedge was scrolled, so its tooltip follows.
    if index == View.tooltipIndex then
        View.tooltipIndex = nil
        SetActionTooltip(View, index)
    end
end

--- Updates the center's quick action while the menu is open (its scroll submenu was scrolled).
---@param action Action
function Menu_View:SetQuickAction(action)
    if not (View:IsShown() and action) then return end
    View.quickAction = action
    View:SetQuickIcon(Menu_Actions.GetIcon(action), action)
    if View.tooltipIndex == QUICK_TOOLTIP then
        View.tooltipIndex = nil
        SetActionTooltip(View, QUICK_TOOLTIP)
    end
end

--- Closes the menu, with the close animation once it was revealed.
function Menu_View:Close()
    if not View:IsShown() then return end
    SetActionTooltip(View, nil)

    -- Closed before the reveal delay passed (a tap), so nothing was visible, and it just hides.
    if not View.revealStart then
        View:SetScript("OnUpdate", nil)
        View:Hide()
        Guide:Hide()
        return
    end

    View.closing = true
    View.closeStart = GetTime()
    View:SetPointerAngle(nil)
    View:SetSelection(nil)
    if View.useGuide then Guide:Update(nil, nil, true) end
end
