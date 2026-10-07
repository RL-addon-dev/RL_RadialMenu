--[[
    Insecure in-game ring: a Ring_Layout wheel plus open/close animation and live selection.

    Driven by the secure controller via CallMethod. Mirrors the secure selection math
    every frame so the highlight matches what will fire on release.
]]

local env = select(2, ...)
local Config = env.Config
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Display = env.AX_Modules:Import("@\\Ring\\Display")
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Layout = env.AX_Modules:Import("@\\Ring\\Layout")
local Ring_View = env.AX_Modules:New("@\\Ring\\View")

local GetCursorPosition, GetTime = GetCursorPosition, GetTime
local atan2, min, max = math.atan2, math.min, math.max

-- Blizzard values (large wheel)
local INTRO_DURATION = 0.2
local OUTRO_DURATION = 0.13
local ANIM_DISTANCE = 20

-- Icon states (resources, range, active): range has no event of its own, so all of them are
-- refreshed this often while open. Blizzard's action bars check range on the same interval.
local STATE_INTERVAL = TOOLTIP_UPDATE_TIME or 0.2

local function Clamp01(value) return min(max(value, 0), 1) end

local function InOutCubic(p)
    if p < 0.5 then return 4 * p * p * p end
    local f = -2 * p + 2
    return 1 - f * f * f / 2
end

-- Fixed position: optional outline of the gesture at the key-down spot (Ring_CursorGuide).
local Guide = env.AX_Modules:Import("@\\Ring\\CursorGuide").Frame

local View = Ring_Layout.CreateWheel(UIParent, "RLRM_RingView")
View:SetFrameStrata("FULLSCREEN_DIALOG")
View:SetShowStates(true)
View:Hide()

local function UpdateCenter(self, inDeadzone, moved)
    if self.isSingleCentered then
        -- The lone slice fires unless the cursor left the center and came back (cancel).
        local cancel = moved and inDeadzone
        self:SetCenter(not cancel, true)
        return
    end
    self:SetCenter(not moved and self.quickSlice ~= nil, inDeadzone)
end

--- Steps the reveal (after the reveal delay) or close animation: fade plus the icons sliding out.
--- @return boolean alive false once the close animation has finished and the view is hidden
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

--- With Show Action Tooltips: the tooltip of what a release would fire, at the HUD Tooltip position
--- (Edit Mode), like an action button's. `index`: a slice index, "quick" (the center's quick
--- action) or nil (hide). Re-shown only when it changes.
local function SetActionTooltip(self, index)
    if index == self.tooltipIndex then return end
    self.tooltipIndex = index
    local slice = index and self.showTooltips and (index == "quick" and self.quickSlice or self.slices[index])
    if not slice then
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        return
    end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    end
    if not Ring_Actions.SetTooltip(GameTooltip, slice) then
        GameTooltip:SetText(Ring_Actions.GetLabel(slice), 1, 1, 1) -- nothing richer than a name
    end
    GameTooltip:Show()
end

--- Every frame while open: animation, then the highlight, pointer and center for the cursor.
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

    -- Same rules as the secure snippet (Ring_Secure). Select From = Menu Center: nothing is
    -- picked until the cursor leaves the quick action square, wherever it is over the menu.
    local index
    if not (self.fromMenu and not moved) then
        index = Ring_Layout.GetSliceIndex(dx, dy, #self.ring.slices, self.deadzone)
    end
    self:SetSelection(index)
    -- What a release would fire: the highlighted slice, else the center (the quick action, or a
    -- lone slice) until the cursor has left it. Not before the menu is revealed: a tap never shows one.
    local tooltip = index
    if not index and not moved then
        tooltip = self.isSingleCentered and 1 or (self.quickSlice and "quick") or nil
    end
    SetActionTooltip(self, self.revealStart and tooltip or nil)
    self:SetPointerAngle(index and atan2(dy, dx) or nil)
    if self.useGuide then Guide:Update(index, index and atan2(dy, dx) or nil, moved) end
    UpdateCenter(self, index == nil, moved)
end



--- @param ring table
--- @param startX number cursor x at key down, UIParent units
--- @param startY number
--- @param probe Frame secure center probe (read-only here)
--- @param quickSlice table|nil slice the quick action would fire
--- @param displaySlices table|nil what each wedge shows (nested scroll slices show the child's
---                     current slice); defaults to ring.slices
function Ring_View:Open(ring, startX, startY, probe, quickSlice, displaySlices)
    View.ring = ring
    View.startX, View.startY = startX, startY
    View.probe = probe
    View.quickSlice = quickSlice
    View.openTime = GetTime()
    View.revealDelay = Ring_Data.GetRevealDelay()
    View.deadzone = Ring_Data.GetDeadzone()
    View.revealStart = nil
    View.closing = false
    View.nextStateUpdate = nil
    View.animatedOffset = -ANIM_DISTANCE

    View:SetShowLabels(Config.DBGlobal:GetVariable("ShowActionNames"))
    View.showTooltips = Config.DBGlobal:GetVariable("ShowActionTooltips") and true or false
    -- Opened again without closing (another menu's key pressed while one is held): drop its tooltip.
    if GameTooltip:GetOwner() == View then GameTooltip:Hide() end
    View.tooltipIndex = nil
    View:SetSlices(displaySlices or ring.slices, View.animatedOffset, ring.quickSlice ~= nil)
    View:SetScrollBadges(ring.slices, true)
    View:SetQuickIcon(quickSlice and Ring_Actions.GetIcon(quickSlice), quickSlice)
    View:SetPointerAngle(nil)
    UpdateCenter(View, true, false)

    -- Position/size are visual only; selection stays relative to startX/startY.
    -- SetPoint offsets are in the view's own (scaled) units.
    local scale = Ring_Display.GetScale()
    local centerX, centerY = Ring_Display.GetCenter(startX, startY)
    View:SetScale(scale)
    View:ClearAllPoints()
    View:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX / scale, centerY / scale)
    View:SetAlpha(0)

    -- Where angles are measured from: the key-down cursor spot, or the fixed menu's center with
    -- Select From = Menu Center (the secure snippet uses the same center, see Ring_Secure).
    View.originX, View.originY = startX, startY
    local fixedX, fixedY = Ring_Display.GetFixedCenter()
    View.fromMenu = Ring_Display.IsSelectFromMenu() and fixedX ~= nil
    if View.fromMenu then View.originX, View.originY = fixedX, fixedY end

    -- Fixed position: optional guide at the key-down cursor spot (UIParent units, like startX/Y).
    -- Not when selecting from the menu's position: there you point at the menu itself.
    View.useGuide = Ring_Display.IsFixed() and not View.fromMenu
        and Config.DBGlobal:GetVariable("CursorGuide") and true or false
    if View.useGuide then
        Guide:Setup(#ring.slices, View.deadzone, Ring_Data.GetProbeSize(), View.quickSlice ~= nil)
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

--- Updates one wedge's icon while the ring is open (mouse wheel on a nested scroll slice).
function Ring_View:SetSliceIcon(index, slice)
    if not View:IsShown() then return end
    View:SetSliceSlice(index, slice)
    -- Scrolled the highlighted slot: its tooltip follows.
    if index == View.tooltipIndex then
        View.tooltipIndex = nil
        SetActionTooltip(View, index)
    end
end

--- Updates the center's quick action while the ring is open (its scroll slice was scrolled).
function Ring_View:SetQuickSlice(slice)
    if not (View:IsShown() and slice) then return end
    View.quickSlice = slice
    View:SetQuickIcon(Ring_Actions.GetIcon(slice), slice)
    if View.tooltipIndex == "quick" then
        View.tooltipIndex = nil
        SetActionTooltip(View, "quick")
    end
end

function Ring_View:Close()
    if not View:IsShown() then return end
    SetActionTooltip(View, nil)

    -- Closed before the reveal delay passed (a tap): nothing was visible, just hide.
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
