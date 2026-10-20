--[[
    Ring_Layout (see Geometry.lua): the wheel itself. CreateWheel returns a plain frame, and its
    callers own its position, scale, animation and input.
]]

local env = select(2, ...)
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Path = env.AX_Modules:Import("ax_modules\\path")
local Ring_Layout = env.AX_Modules:Import("@\\Ring\\Layout")
local Private = env.AX_Modules:Import("@\\Ring\\Layout\\Private")

local sin, cos = math.sin, math.cos

local ATLAS_BACKGROUND  = "Radial_Wheel_BG"
local ATLAS_POINTER     = "Radial_Wheel_Select_Pointer"
local ATLAS_CANCEL_ICON = "Radial_Wheel_Icon_Close"
local ATLAS_FRAME       = "Radial_Wheel_Frame_Count_%d"

-- Blizzard's values (the large wheel).
local WHEEL_SIZE       = 375
local UNSELECTED_SCALE = 0.9
local WEDGE_FRAME_SIZE = 100

local ICON_SIZE       = 40
local QUICK_ICON_SIZE = 26
-- Between an icon and its action name, outward. It keeps the name clear of a badge on the icon's
-- corner (which pokes out about 14px), and is the same for every action, so names sit evenly.
local LABEL_GAP = 20
-- The visibility badge on the center (quick action) icon, scaled to its smaller size.
local QUICK_BADGE_SCALE = QUICK_ICON_SIZE / ICON_SIZE
-- A menu with a single action shows it in the center, at the quick action icon's size.
local SINGLE_ICON_SCALE = QUICK_ICON_SIZE / ICON_SIZE

-- Drawn dividers, for counts without Blizzard's frame art. They copy Radial_Wheel_Frame_Count_4's
-- lines, fading out from the center.
local DIVIDER_OUTER_RADIUS = 190 -- past the background shadow, like the 4-slice frame art
local DIVIDER_THICKNESS    = 3
local DIVIDER_COLOR_INNER  = CreateColor(0x38 / 255, 0x34 / 255, 0x30 / 255, 1) -- #383430
local DIVIDER_COLOR_OUTER  = CreateColor(0x38 / 255, 0x34 / 255, 0x30 / 255, 0)

-- The ring around the center, for counts without frame art. It's Radial_Wheel_Frame_Count_4
-- masked to a circle just past its ring, with a small margin so the ring's outer edge isn't clipped.
local CIRCLE_MASK_TEXTURE     = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CENTER_RING_MASK_MARGIN = 2

-- With nothing around the center (a lone action sits in it, or there are no actions), the wheel's
-- background is masked to just past the center circle. Mask_SoftCircle.png is opaque out to 80% of
-- its radius, then fades out. Its diameter is this many times the center circle's.
local SINGLE_BACKGROUND_MASK_PATH  = "%s\\Art\\Ring\\Mask_SoftCircle.png"
local SINGLE_BACKGROUND_MASK_SCALE = 1.35
local SINGLE_BACKGROUND_ALPHA      = 0.6 -- lighter than the full wheel's shade

Ring_Layout.ATLAS_CANCEL_ICON = ATLAS_CANCEL_ICON -- the preview's X buttons



-- Wheel

--- One action's place on the wheel (WheelMixin:GetWedge).
---@class RingWedge : Frame
---@field index integer
---@field angle number its middle, in radians (Ring_Layout.GetSliceAngle)
---@field Pieces table[] the highlight art (WedgeArt.lua)
---@field pieceCount integer how many pieces the current count uses
---@field Button ActionIcon
---@field Label FontString the action's name
---@field ScrollBadge ScrollBadge
---@field ExpandBadge ExpandBadge
---@field ConditionBadge ConditionBadge
---@field RemoveButton Button? the settings preview's X (Rings_Preview)

--- A wheel (Ring_Layout.CreateWheel). WheelMixin holds its methods, and Badges.lua adds some.
---@class RingWheel : Frame
---@field Background Texture
---@field BackgroundMask MaskTexture
---@field backgroundMasked boolean
---@field Frame Texture Blizzard's frame art for this count
---@field Pointer Texture
---@field CenterRing Texture
---@field CenterRingMask MaskTexture
---@field CancelSelected Texture
---@field CancelIcon Texture
---@field Quick ActionIcon the center's quick action icon
---@field QuickBadges table the quick action's badges ({ Button, ConditionBadge })
---@field Wedges RingWedge[] one per action, made on first use (GetWedge) and reused
---@field Dividers Line[]
---@field sliceCount integer
---@field slices Slice[] what each wedge shows
---@field quickSlice Slice?
---@field isSingleCentered boolean a lone action sits in the center (SetSlices)
---@field selectedIndex integer?
---@field iconRadiusExtra number
---@field showLabels boolean
---@field showStates boolean
---@field onWedgeCreated fun(wheel: RingWheel, wedge: RingWedge)? set by the settings preview
---@field preview RingPreview? the settings preview it belongs to
local WheelMixin = {}
Private.WheelMixin = WheelMixin -- Badges.lua adds its methods

--- Puts the action's name beside its icon, away from the center. It shows while the wedge is
--- highlighted (SetWedgeSelected), when names are on (SetShowLabels).
---@param wedge RingWedge
---@param slice Slice?
local function SetWedgeLabel(wedge, slice)
    local label = wedge.Label
    local point, ownerPoint = Ring_Layout.GetOutwardPoints(wedge.angle)
    label:ClearAllPoints()
    label:SetPoint(point, wedge.Button, ownerPoint, cos(wedge.angle) * LABEL_GAP, sin(wedge.angle) * LABEL_GAP)
    label:SetText(slice and Ring_Actions.GetLabel(slice) or nil)
end

--- Wedge `index`, made on first use: its icon, badges and name.
---@param index integer
---@return RingWedge
function WheelMixin:GetWedge(index)
    local wedge = self.Wedges[index]
    if wedge then return wedge end

    wedge = CreateFrame("Frame", nil, self) --[[@as RingWedge]]
    wedge:SetUsingParentLevel(true)
    wedge:SetSize(WEDGE_FRAME_SIZE, WEDGE_FRAME_SIZE)
    wedge.index = index

    wedge.Pieces = {} -- the highlight art (WedgeArt.lua)
    wedge.Button = Ring_Layout.CreateActionIcon(wedge, ICON_SIZE)
    Private.CreateScrollBadge(self, wedge)
    Private.CreateConditionBadge(self, wedge)
    -- The action name, shown while highlighted (SetShowLabels). It's a child of the wheel, not of
    -- the icon, so it doesn't grow with the selected icon, but it follows it (anchored to it)
    -- through the slide.
    wedge.Label = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    wedge.Label:SetWordWrap(false)
    wedge.Label:SetShadowOffset(1, -1)
    wedge.Label:Hide()

    self.Wedges[index] = wedge
    if self.onWedgeCreated then self.onWedgeCreated(self, wedge) end
    return wedge
end

--- Divider line `index`, made on first use.
---@param index integer
---@return Line
function WheelMixin:GetDivider(index)
    local line = self.Dividers[index]
    if not line then
        line = self:CreateLine(nil, "ARTWORK", nil, -2)
        line:SetThickness(DIVIDER_THICKNESS)
        line:SetTexture(Private.WHITE_TEXTURE)
        line:SetGradient("HORIZONTAL", DIVIDER_COLOR_INNER, DIVIDER_COLOR_OUTER) -- from start to end point
        self.Dividers[index] = line
    end
    return line
end

--- The wheel's frame: Blizzard's frame art when this count has it, else drawn dividers and a ring
--- around the center.
---@param count integer
function WheelMixin:SetupFrameTexture(count)
    local frameAtlas = ATLAS_FRAME:format(count)
    local useAtlas = count > 0 and Private.HasAtlas(frameAtlas)

    self.Frame:SetShown(useAtlas)
    if useAtlas then self.Frame:SetAtlas(frameAtlas, true) end
    self.CenterRing:SetShown(not useAtlas and count > 0)

    -- Dividers start at the cancel button's outline (the selected ring art, drawn at atlas size).
    local innerRadius = Private.GetDividerStartRadius()

    -- A single action has no boundaries to draw.
    local dividerCount = (useAtlas or count < 2) and 0 or count
    for i = 1, dividerCount do
        local angle = Ring_Layout.GetBoundaryAngle(i, count)
        local line = self:GetDivider(i)
        local c, s = cos(angle), sin(angle)
        line:SetStartPoint("CENTER", self, c * innerRadius, s * innerRadius)
        line:SetEndPoint("CENTER", self, c * DIVIDER_OUTER_RADIUS, s * DIVIDER_OUTER_RADIUS)
        line:Show()
    end
    for i = dividerCount + 1, #self.Dividers do
        self.Dividers[i]:Hide()
    end
end

--- With nothing around the center (a lone action in it, or no actions), the background only
--- shades around the center circle, and more lightly.
---@param centerOnly boolean
function WheelMixin:SetBackgroundCenterOnly(centerOnly)
    if centerOnly ~= self.backgroundMasked then
        if centerOnly then
            self.Background:AddMaskTexture(self.BackgroundMask)
        else
            self.Background:RemoveMaskTexture(self.BackgroundMask)
        end
        self.backgroundMasked = centerOnly
    end
    self.Background:SetAlpha(centerOnly and SINGLE_BACKGROUND_ALPHA or 1)
end

--- Places wedge `index` of `count` and shows `slice` on it, unselected.
---@param index integer
---@param count integer
---@param slice Slice
function WheelMixin:LayoutWedge(index, count, slice)
    local wedge = self:GetWedge(index)
    local angle = Ring_Layout.GetSliceAngle(index, count)
    wedge.angle = angle

    wedge:ClearAllPoints()
    wedge:SetPoint("CENTER", self, "CENTER", cos(angle) * Private.WEDGE_SPACING, sin(angle) * Private.WEDGE_SPACING)
    Private.SetupWedgeArt(wedge, count, angle)

    Ring_Layout.SetSliceIcon(wedge.Button, slice)
    SetWedgeLabel(wedge, slice)
    self:SetWedgeSelected(wedge, false)
    wedge.Button:Show() -- SetCenter may have hidden it while this was a single-action menu
    wedge:Show()
end

--- Lays out one wedge per action, with their icons and highlight art.
---@param slices Slice[]
---@param iconOffset number? extra radial icon offset (the open and close animation)
---@param hasTapOnly boolean? the menu has a tap-only quick action, which keeps the center
function WheelMixin:SetSlices(slices, iconOffset, hasTapOnly)
    local count = #slices
    self.sliceCount = count
    self.iconRadiusExtra = Ring_Layout.GetIconRadius(count) - Private.WEDGE_SPACING
    -- A lone action has no direction to pick, so its icon sits in the center (where the quick
    -- action shows) instead of on a wedge, and a tap fires it. SetCenter swaps it with the cancel
    -- icon. That's not done when a tap-only quick action owns the center (Ring_Secure fires that
    -- on a tap).
    self.isSingleCentered = count == 1 and not hasTapOnly
    self.selectedIndex = nil
    self:SetBackgroundCenterOnly(self.isSingleCentered or count == 0)

    self:SetupFrameTexture(count)

    for i = 1, count do self:LayoutWedge(i, count, slices[i]) end
    for i = count + 1, #self.Wedges do
        self.Wedges[i]:Hide()
        self.Wedges[i].Label:Hide()
    end

    self:PositionIcons(iconOffset or 0)

    -- Our own copy, because callers may pass a menu's stored actions, and SetSliceSlice replaces
    -- entries.
    self.slices = {}
    for i = 1, count do self.slices[i] = slices[i] end
    self:UpdateCooldowns()
    self:UpdateStates(true)
end

--- Places the icons on their wedges.
---@param offset number extra radial offset for every icon (the open and close animation)
function WheelMixin:PositionIcons(offset)
    offset = offset + (self.iconRadiusExtra or 0)
    for i = 1, self.sliceCount or 0 do
        local wedge = self.Wedges[i]
        wedge.Button:ClearAllPoints()
        if self.isSingleCentered then
            wedge.Button:SetPoint("CENTER", self, "CENTER")
        else
            wedge.Button:SetPoint("CENTER", cos(wedge.angle) * offset, sin(wedge.angle) * offset)
        end
    end
end

--- Highlights `wedge` or not. Highlighted, it shows its art, a full-size icon and (with names on)
--- the action's name.
---@param wedge RingWedge
---@param selected boolean
function WheelMixin:SetWedgeSelected(wedge, selected)
    if self.isSingleCentered then
        -- In the center, it's the quick action, which shows no name.
        Private.SetWedgeArtShown(wedge, false)
        wedge.Button:SetScale(SINGLE_ICON_SCALE)
        wedge.Label:Hide()
        return
    end
    Private.SetWedgeArtShown(wedge, selected)
    wedge.Button:SetScale(selected and 1 or UNSELECTED_SCALE)
    wedge.Label:SetShown(selected and self.showLabels or false)
end

--- Highlights one wedge (nil for none).
---@param index integer?
function WheelMixin:SetSelection(index)
    if index == self.selectedIndex then return end
    if self.selectedIndex and self.Wedges[self.selectedIndex] then
        self:SetWedgeSelected(self.Wedges[self.selectedIndex], false)
    end
    if index then self:SetWedgeSelected(self.Wedges[index], true) end
    self.selectedIndex = index
end

--- Points the pointer at `angle` (radians), or hides it with nil.
---@param angle number?
function WheelMixin:SetPointerAngle(angle)
    if self.isSingleCentered then angle = nil end
    self.Pointer:SetShown(angle ~= nil)
    if angle then self.Pointer:SetRotation(angle) end
end

--- What the center shows.
---@param showQuick boolean the quick action icon instead of the cancel icon
---@param highlighted boolean the cancel button's selected ring
function WheelMixin:SetCenter(showQuick, highlighted)
    if self.isSingleCentered then
        -- The action's own icon is the quick action.
        self.Wedges[1].Button:SetShown(showQuick)
        self.Quick:Hide()
    else
        self.Quick:SetShown(showQuick)
    end
    self.CancelIcon:SetShown(not showQuick)
    self.CancelSelected:SetShown(highlighted)
end

--- Shows every icon's current cooldown.
function WheelMixin:UpdateCooldowns()
    for i = 1, self.sliceCount or 0 do
        Ring_Layout.UpdateIconCooldown(self.Wedges[i].Button, self.slices[i])
    end
    Ring_Layout.UpdateIconCooldown(self.Quick, self.quickSlice)
end

--- Icon states (usable, in range, active, see Ring_Layout.UpdateIconState). Only the in-game menu
--- shows them, and refreshes them while open (Ring_View). The settings preview keeps plain icons.
---@param shown boolean
function WheelMixin:SetShowStates(shown)
    self.showStates = shown
end

--- Shows every icon's current state, when states are on.
---@param fresh boolean? the icons were just given their actions (Ring_Layout.UpdateIconState)
function WheelMixin:UpdateStates(fresh)
    if not self.showStates then return end
    for i = 1, self.sliceCount or 0 do
        Ring_Layout.UpdateIconState(self.Wedges[i].Button, self.slices[i], fresh)
    end
    Ring_Layout.UpdateIconState(self.Quick, self.quickSlice, fresh)
end

--- Replaces what one wedge shows (a scroll submenu scrolled to another action).
---@param index integer
---@param slice Slice?
function WheelMixin:SetSliceSlice(index, slice)
    local wedge = self.Wedges[index]
    if not (wedge and slice) then return end
    self.slices[index] = slice
    Ring_Layout.SetSliceIcon(wedge.Button, slice)
    SetWedgeLabel(wedge, slice)
    Ring_Layout.UpdateIconCooldown(wedge.Button, slice)
    if self.showStates then Ring_Layout.UpdateIconState(wedge.Button, slice, true) end
end

--- Whether the highlighted action's name shows beside its icon. The in-game menu follows the Show
--- Action Names setting, and the preview uses tooltips instead. The center (quick action) shows
--- none.
---@param shown boolean
function WheelMixin:SetShowLabels(shown)
    self.showLabels = shown and true or false
end

--- Shows the center's selected ring. A single-action menu always shows it, because its center is
--- the action (like the in-game menu, see Ring_View).
---@param shown boolean
function WheelMixin:SetCenterHighlight(shown)
    self.CancelSelected:SetShown(shown or self.isSingleCentered or false)
end

--- Shows the center's quick action icon.
---@param icon number|string|nil
---@param slice Slice? the action the icon stands for, for its border and cooldown (nil for none)
function WheelMixin:SetQuickIcon(icon, slice)
    Ring_Layout.SetIcon(self.Quick.Icon, icon)
    self.Quick.Border:SetShown(not (slice and Ring_Actions.HasNoIconBorder(slice)))
    Ring_Layout.SetUnderlay(self.Quick, slice)
    self.quickSlice = slice
    Ring_Layout.UpdateIconCooldown(self.Quick, slice)
    if self.showStates then Ring_Layout.UpdateIconState(self.Quick, slice, true) end
end



-- Creating the wheel

--- The wheel's shade, and its mask for when only the center is used (SetBackgroundCenterOnly).
---@param wheel RingWheel
local function CreateBackground(wheel)
    wheel.Background = wheel:CreateTexture(nil, "BACKGROUND", nil, 1)
    wheel.Background:SetPoint("CENTER")
    wheel.Background:SetAtlas(ATLAS_BACKGROUND, true)
    wheel.BackgroundMask = wheel:CreateMaskTexture()
    wheel.BackgroundMask:SetTexture(SINGLE_BACKGROUND_MASK_PATH:format(Path.Root), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    wheel.BackgroundMask:SetPoint("CENTER")
    local maskSize = 2 * Private.GetCenterRadius() * SINGLE_BACKGROUND_MASK_SCALE
    wheel.BackgroundMask:SetSize(maskSize, maskSize)
    wheel.backgroundMasked = false
end

--- Blizzard's frame art and the pointer.
---@param wheel RingWheel
local function CreateFrameArt(wheel)
    wheel.Frame = wheel:CreateTexture(nil, "OVERLAY", nil, 1)
    wheel.Frame:SetPoint("CENTER")

    wheel.Pointer = wheel:CreateTexture(nil, "OVERLAY", nil, 2)
    wheel.Pointer:SetPoint("CENTER")
    wheel.Pointer:SetAtlas(ATLAS_POINTER, true)
    wheel.Pointer:Hide()
end

--- The ring around the center, for counts without frame art. It's Blizzard's 4-slice frame art
--- cropped to its center circle (its diagonal lines start at the circle's edge), so its color,
--- thickness and clear center match the 4-slice wheel exactly.
---@param wheel RingWheel
local function CreateCenterRing(wheel)
    wheel.CenterRing = wheel:CreateTexture(nil, "ARTWORK", nil, -1)
    wheel.CenterRing:SetPoint("CENTER")
    wheel.CenterRing:SetAtlas(ATLAS_FRAME:format(Private.FALLBACK_WEDGE_COUNT), true)
    local circleRadius = Private.GetDividerStartRadius() + CENTER_RING_MASK_MARGIN
    wheel.CenterRingMask = wheel:CreateMaskTexture()
    wheel.CenterRingMask:SetPoint("CENTER")
    wheel.CenterRingMask:SetSize(circleRadius * 2, circleRadius * 2)
    wheel.CenterRingMask:SetTexture(CIRCLE_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    wheel.CenterRing:AddMaskTexture(wheel.CenterRingMask)
    wheel.CenterRing:Hide()
end

--- The center: the cancel button's art and the quick action icon, with its visibility badge.
---@param wheel RingWheel
local function CreateCenter(wheel)
    -- Above the frame art (OVERLAY 1), whose center circle would otherwise dim it on 4-slice
    -- menus. It shares a sublevel with the pointer, which is hidden while this is shown.
    wheel.CancelSelected = wheel:CreateTexture(nil, "OVERLAY", nil, 2)
    wheel.CancelSelected:SetPoint("CENTER")
    wheel.CancelSelected:SetAtlas(Private.ATLAS_CANCEL_SELECTED, true)

    wheel.CancelIcon = wheel:CreateTexture(nil, "OVERLAY", nil, 3)
    wheel.CancelIcon:SetPoint("CENTER")
    wheel.CancelIcon:SetAtlas(ATLAS_CANCEL_ICON, true)

    wheel.Quick = Ring_Layout.CreateActionIcon(wheel, QUICK_ICON_SIZE)
    -- The quick action's visibility badge (settings preview only).
    wheel.QuickBadges = { Button = wheel.Quick }
    Private.CreateConditionBadge(wheel, wheel.QuickBadges)
    wheel.QuickBadges.ConditionBadge:SetScale(QUICK_BADGE_SCALE)
    wheel.Quick:SetPoint("CENTER")
    wheel.Quick:Hide()
end

--- Keeps cooldowns current while the wheel is on screen. The events are only listened to then
--- (this child frame is shown and hidden with the wheel), not on every global cooldown in combat
--- while it's closed.
---@param wheel RingWheel
local function ListenForCooldowns(wheel)
    local events = CreateFrame("Frame", nil, wheel)
    local function Listen(self)
        for _, event in ipairs(Private.COOLDOWN_EVENTS) do self:RegisterEvent(event) end
    end
    events:SetScript("OnShow", Listen)
    events:SetScript("OnHide", events.UnregisterAllEvents)
    events:SetScript("OnEvent", function() wheel:UpdateCooldowns() end)
    if events:IsVisible() then Listen(events) end
end

--- A new wheel, with no actions yet (SetSlices).
---@param parent Frame
---@param name string?
---@return RingWheel
function Ring_Layout.CreateWheel(parent, name)
    local wheel = CreateFrame("Frame", name, parent) --[[@as RingWheel]]
    wheel:SetSize(WHEEL_SIZE, WHEEL_SIZE)

    CreateBackground(wheel)
    CreateFrameArt(wheel)
    CreateCenterRing(wheel)
    CreateCenter(wheel)

    wheel.Wedges = {}
    wheel.Dividers = {}
    wheel.sliceCount = 0
    wheel.slices = {}

    ListenForCooldowns(wheel)

    Mixin(wheel, WheelMixin)
    return wheel
end
