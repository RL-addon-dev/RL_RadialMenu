--[[
    Shared wheel geometry and art, modelled on Blizzard's RadialWheelFrameTemplate (ping wheel):
    Blizzard_SharedXML/Blizzard_RadialWheel.xml/.lua

    Used by the in-game ring (Ring_View) and the settings preview (Setting/Rings), so both draw
    the exact same wheel. `CreateWheel` returns a plain frame; callers own position, scale,
    animation and input.

    Slices are laid out clockwise starting at the top (Blizzard lays out counter-clockwise;
    our order must match the secure snippet in Ring_Secure).
]]

local env = select(2, ...)
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Path = env.AX_Modules:Import("ax_modules\\path")
local Ring_Layout = env.AX_Modules:New("@\\Ring\\Layout")
local Private = env.AX_Modules:New("@\\Ring\\Layout\\Private")

local GetAtlasInfo = C_Texture.GetAtlasInfo
local deg, atan2, floor, rad, sin, cos, pi = math.deg, math.atan2, math.floor, math.rad, math.sin, math.cos, math.pi
local TWO_PI = 2 * pi

local ATLAS_BACKGROUND = "Radial_Wheel_BG"
local ATLAS_POINTER = "Radial_Wheel_Select_Pointer"
local ATLAS_CANCEL_ICON = "Radial_Wheel_Icon_Close"
local ATLAS_CANCEL_SELECTED = "Radial_Wheel_Select_Close"
local ATLAS_FRAME = "Radial_Wheel_Frame_Count_%d"
local ATLAS_WEDGE = "Radial_Wheel_Select_Wedge_Count_%d"
local FALLBACK_WEDGE_COUNT = 4 -- the ping wheel's own count, assumed to always exist

-- Blizzard values (large wheel)
local WHEEL_SIZE = 375
local WEDGE_SPACING = 80
local WEDGE_SELECTED_SPACING = 20
local UNSELECTED_SCALE = 0.9
-- Rings with many slices push their icons outward so neighbours keep this much center-to-center
-- distance (icon plus a gap). Only the icons move; wedge art stays at WEDGE_SPACING.
local ICON_MIN_SPACING = 58
local ICON_MAX_RADIUS = 140

local ICON_SIZE = 40
local QUICK_ICON_SIZE = 26
-- Between an icon and its action name, outward: clear of a badge on the icon's corner (it pokes
-- out ~14px), the same for every action so the names sit evenly around the wheel.
local LABEL_GAP = 20
-- Visibility badge on the center (quick action) icon, scaled to its smaller size.
local QUICK_BADGE_SCALE = QUICK_ICON_SIZE / ICON_SIZE
-- A ring with a single slice shows it in the center, at the quick action icon's size.
local SINGLE_ICON_SCALE = QUICK_ICON_SIZE / ICON_SIZE
local CLIP_MASK_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CLIP_MASK_SIZE = 512 -- large enough to cover the whole wedge art along each edge
local DIVIDER_INNER_RADIUS = 28
local DIVIDER_OUTER_RADIUS = 190 -- past the background shadow, like the 4-slice frame art
-- Drawn dividers mimic Radial_Wheel_Frame_Count_4's lines, fading out from the center.
local DIVIDER_THICKNESS = 3
local DIVIDER_COLOR_INNER = CreateColor(0x38 / 255, 0x34 / 255, 0x30 / 255, 1) -- #383430
local DIVIDER_COLOR_OUTER = CreateColor(0x38 / 255, 0x34 / 255, 0x30 / 255, 0)
-- The cancel ring atlas has transparent padding around the visible circle; dividers start this far
-- inside its edge and are drawn under the center ring, so they meet it without a gap.
local DIVIDER_INNER_OVERLAP = 3
-- Circle around the center for counts without frame art: Radial_Wheel_Frame_Count_4 masked to a
-- circle just past its ring (a little margin so the ring's outer edge isn't clipped).
local CIRCLE_MASK_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CENTER_RING_MASK_MARGIN = 2
-- A lone slice sits in the center: the wheel's background (as dark as usual) is masked to just
-- past the center circle. Mask_SoftCircle.png is opaque out to 80% of its radius, then fades out;
-- this is its diameter as a share of the center circle's.
local SINGLE_BACKGROUND_MASK_PATH = "%s\\Art\\Ring\\Mask_SoftCircle.png"
local SINGLE_BACKGROUND_MASK_SCALE = 1.35
local SINGLE_BACKGROUND_ALPHA = 0.6 -- lighter than the full wheel's shade

Ring_Layout.ATLAS_CANCEL_ICON = ATLAS_CANCEL_ICON -- the preview's X buttons

local function HasAtlas(name) return GetAtlasInfo(name) ~= nil end
Private.HasAtlas = HasAtlas
Private.FILL_TEXTURE = CLIP_MASK_TEXTURE




-- Geometry

--- Same math as the secure snippet in Ring_Secure.
function Ring_Layout.GetSliceIndex(dx, dy, count, deadzone)
    if count == 0 or dx * dx + dy * dy <= deadzone * deadzone then return nil end
    local step = 360 / count
    local offset = (90 - deg(atan2(dy, dx))) % 360
    return floor((offset + step / 2) / step) % count + 1
end

--- Radians, counter-clockwise from +x (the convention SetRotation uses).
function Ring_Layout.GetSliceAngle(index, count)
    return (rad(90 - (index - 1) * 360 / count)) % TWO_PI
end
local GetSliceAngle = Ring_Layout.GetSliceAngle




-- Selected wedge art

-- Our own highlight art for 2 and 3 slices (Blizzard has none, and copies of the 4-slice art
-- show seams). Art/Ring/Wedge_Count_N.png: wheel center at the image center, wedge pointing
-- right, inner arc at CUSTOM_WEDGE_INNER_FRAC of the half size; sized so that arc sits on the
-- center circle.
local CUSTOM_WEDGE_PATH = "%s\\Art\\Ring\\Wedge_Count_%d.png"
local CUSTOM_WEDGE_COUNTS = { [2] = true, [3] = true }
-- Baked into the images (made with a script kept outside the repo): change both together.
local CUSTOM_WEDGE_INNER_FRAC = 0.11

-- Widest share of a slice one copy of the 4-slice art (90 degrees wide) may cover. Below 90 so
-- each copy's own straight edges are always clipped away; a wider slice (fewer than 4 slices)
-- is drawn as several rotated copies side by side.
local MAX_PIECE_ARC = rad(80)

--- One copy of the wedge art plus two half-plane masks whose edges run along its sector's
--- boundary lines through the wheel center. Together the masks cut the art down to exactly that
--- sector, leaving Blizzard's inner arc around the cancel button untouched.
local function GetPiece(wedge, index)
    local piece = wedge.Pieces[index]
    if piece then return piece end

    piece = { texture = wedge:CreateTexture(nil, "ARTWORK"), masks = {} }
    for i = 1, 2 do
        local mask = wedge:CreateMaskTexture()
        mask:SetTexture(CLIP_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(CLIP_MASK_SIZE, CLIP_MASK_SIZE)
        piece.masks[i] = mask
    end
    piece.texture:Hide()
    wedge.Pieces[index] = piece
    return piece
end

local function SetPieceClipped(piece, clipped)
    if piece.clipped == clipped then return end
    for _, mask in ipairs(piece.masks) do
        if clipped then piece.texture:AddMaskTexture(mask) else piece.texture:RemoveMaskTexture(mask) end
    end
    piece.clipped = clipped
end

--- Clips `piece` to the sector between angles `low` and `high` (radians, around the wheel center).
--- `wedgeAngle` is the slice's angle, which places the wedge frame the masks are anchored to.
local function ClipPiece(piece, wedge, wedgeAngle, low, high)
    -- Wheel center, relative to the wedge frame's center.
    local centerX, centerY = -cos(wedgeAngle) * WEDGE_SPACING, -sin(wedgeAngle) * WEDGE_SPACING
    local edges = {
        { angle = high, inward = high - pi / 2 },
        { angle = low,  inward = low + pi / 2 },
    }
    local distance = CLIP_MASK_SIZE / 2
    for i, edge in ipairs(edges) do
        local mask = piece.masks[i]
        mask:ClearAllPoints()
        mask:SetPoint("CENTER", wedge, "CENTER", centerX + cos(edge.inward) * distance, centerY + sin(edge.inward) * distance)
        mask:SetRotation(edge.angle)
    end
    SetPieceClipped(piece, true)
end

--- Rotates `piece` to `angle` and places it where Blizzard draws a wedge at that angle.
local function PlacePiece(piece, wedgeAngle, angle)
    local radius = WEDGE_SPACING + WEDGE_SELECTED_SPACING
    local texture = piece.texture
    texture:SetRotation(angle)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", cos(angle) * radius - cos(wedgeAngle) * WEDGE_SPACING,
        sin(angle) * radius - sin(wedgeAngle) * WEDGE_SPACING)
end

--- The art shown behind a highlighted slice: Blizzard's art for this count, our own (2 and 3), or
--- copies of the 4-slice art clipped to the slice's sector.
local function SetupWedgeSelectedTexture(wedge, count, angle)
    local wedgeAtlas = ATLAS_WEDGE:format(count)
    local pieceCount

    if count < 2 then
        pieceCount = 0 -- a single slice sits in the center and never shows wedge art
    elseif HasAtlas(wedgeAtlas) then
        -- Blizzard art made for this count: one unclipped copy.
        local piece = GetPiece(wedge, 1)
        piece.texture:SetAtlas(wedgeAtlas, true)
        SetPieceClipped(piece, false)
        PlacePiece(piece, angle, angle)
        pieceCount = 1
    elseif CUSTOM_WEDGE_COUNTS[count] then
        local piece = GetPiece(wedge, 1)
        local cancelInfo = GetAtlasInfo(ATLAS_CANCEL_SELECTED)
        local innerRadius = (cancelInfo and cancelInfo.width / 2 or DIVIDER_INNER_RADIUS) - DIVIDER_INNER_OVERLAP
        local size = 2 * innerRadius / CUSTOM_WEDGE_INNER_FRAC
        piece.texture:SetTexture(CUSTOM_WEDGE_PATH:format(Path.Root, count))
        piece.texture:SetSize(size, size)
        SetPieceClipped(piece, false)
        -- Centered on the wheel center (given relative to the wedge frame), rotated to the slice.
        piece.texture:SetRotation(angle)
        piece.texture:ClearAllPoints()
        piece.texture:SetPoint("CENTER", -cos(angle) * WEDGE_SPACING, -sin(angle) * WEDGE_SPACING)
        pieceCount = 1
    else
        -- The 4-slice art at its own size, clipped to this slice's sector: one copy for a narrower
        -- slice (more than 4), several rotated copies side by side for a wider one (fewer than 4).
        local arc = 2 * pi / count
        pieceCount = math.ceil(arc / MAX_PIECE_ARC)
        local pieceArc = arc / pieceCount
        local low = angle - arc / 2
        local fallbackAtlas = ATLAS_WEDGE:format(FALLBACK_WEDGE_COUNT)
        for i = 1, pieceCount do
            local piece = GetPiece(wedge, i)
            local pieceLow = low + (i - 1) * pieceArc
            piece.texture:SetAtlas(fallbackAtlas, true)
            PlacePiece(piece, angle, pieceLow + pieceArc / 2)
            ClipPiece(piece, wedge, angle, pieceLow, pieceLow + pieceArc)
        end
    end

    wedge.pieceCount = pieceCount
    for i = pieceCount + 1, #wedge.Pieces do
        wedge.Pieces[i].texture:Hide()
    end
end

local function SetWedgeArtShown(wedge, shown)
    for i = 1, #wedge.Pieces do
        wedge.Pieces[i].texture:SetShown(shown and i <= (wedge.pieceCount or 0))
    end
end



-- Wheel

--- Distance from the wheel center to the slice icons: Blizzard's spacing, or further out when
--- the slices would otherwise crowd each other.
local function GetIconRadius(count)
    if count < 3 then return WEDGE_SPACING end
    local needed = ICON_MIN_SPACING / (2 * sin(pi / count)) -- chord between neighbours
    return math.min(math.max(WEDGE_SPACING, needed), ICON_MAX_RADIUS)
end

Ring_Layout.GetIconRadius = GetIconRadius

local WheelMixin = {}
Private.WheelMixin = WheelMixin -- Badges.lua adds its methods

-- Placing things beside a slice, away from the wheel center (action names here, the preview's
-- tooltips): an axis counts once the direction's component passes this (0.38 ≈ sin 22.5°, so
-- each of the 8 directions covers 45°).
local OUTWARD_AXIS_THRESHOLD = 0.38

--- Anchor points to put something beside `owner`, away from the wheel center along `angle`
--- (radians, counter-clockwise from +x): above a top slice, to the right of a right one, ...
--- @return string point the placed frame's point (its side facing the owner)
--- @return string ownerPoint the owner's point it touches (the owner's outer side)
function Ring_Layout.GetOutwardPoints(angle)
    local c, s = cos(angle), sin(angle)
    local vertical = (s > OUTWARD_AXIS_THRESHOLD and "TOP") or (s < -OUTWARD_AXIS_THRESHOLD and "BOTTOM") or ""
    local horizontal = (c > OUTWARD_AXIS_THRESHOLD and "RIGHT") or (c < -OUTWARD_AXIS_THRESHOLD and "LEFT") or ""
    local opposite = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT", [""] = "" }
    local ownerPoint = vertical .. horizontal
    local point = opposite[vertical] .. opposite[horizontal]
    return point ~= "" and point or "CENTER", ownerPoint ~= "" and ownerPoint or "CENTER"
end

--- Puts the action's name beside its icon, away from the center. It shows while the slice is
--- highlighted (SetWedgeSelected), when names are on (SetShowLabels).
local function SetWedgeLabel(wheel, wedge, slice)
    local label = wedge.Label
    local point, ownerPoint = Ring_Layout.GetOutwardPoints(wedge.angle)
    label:ClearAllPoints()
    label:SetPoint(point, wedge.Button, ownerPoint, cos(wedge.angle) * LABEL_GAP, sin(wedge.angle) * LABEL_GAP)
    label:SetText(slice and Ring_Actions.GetLabel(slice) or nil)
end

function WheelMixin:GetWedge(index)
    local wedge = self.Wedges[index]
    if wedge then return wedge end

    wedge = CreateFrame("Frame", nil, self)
    wedge:SetUsingParentLevel(true)
    wedge:SetSize(100, 100)
    wedge.index = index

    wedge.Pieces = {} -- selected wedge art, see SetupWedgeSelectedTexture
    wedge.Button = Ring_Layout.CreateActionIcon(wedge, ICON_SIZE)
    Private.CreateScrollBadge(self, wedge)
    Private.CreateConditionBadge(self, wedge)
    -- Action name, shown while highlighted (SetShowLabels). A child of the wheel, not the icon:
    -- it doesn't grow with the selected icon, but follows it (anchored to it) through the slide.
    wedge.Label = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    wedge.Label:SetWordWrap(false)
    wedge.Label:SetShadowOffset(1, -1)
    wedge.Label:Hide()

    self.Wedges[index] = wedge
    if self.onWedgeCreated then self.onWedgeCreated(self, wedge) end
    return wedge
end

function WheelMixin:GetDivider(index)
    local line = self.Dividers[index]
    if not line then
        line = self:CreateLine(nil, "ARTWORK", nil, -2)
        line:SetThickness(DIVIDER_THICKNESS)
        line:SetTexture(CLIP_MASK_TEXTURE)
        line:SetGradient("HORIZONTAL", DIVIDER_COLOR_INNER, DIVIDER_COLOR_OUTER) -- start point → end point
        self.Dividers[index] = line
    end
    return line
end

--- The wheel's frame: Blizzard's frame art when this count has it, otherwise drawn dividers and a
--- ring around the center.
function WheelMixin:SetupFrameTexture(count)
    local frameAtlas = ATLAS_FRAME:format(count)
    local useAtlas = count > 0 and HasAtlas(frameAtlas)

    self.Frame:SetShown(useAtlas)
    if useAtlas then self.Frame:SetAtlas(frameAtlas, true) end
    self.CenterRing:SetShown(not useAtlas and count > 0)

    -- Dividers start at the cancel button's outline (the selected ring art, drawn at atlas size).
    local cancelInfo = GetAtlasInfo(ATLAS_CANCEL_SELECTED)
    local innerRadius = (cancelInfo and cancelInfo.width / 2 or DIVIDER_INNER_RADIUS) - DIVIDER_INNER_OVERLAP

    -- A single slice has no boundaries to draw.
    local dividerCount = (useAtlas or count < 2) and 0 or count
    for i = 1, dividerCount do
        local angle = GetSliceAngle(i, count) - pi / count -- boundary after slice i (clockwise)
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

--- Lays out one wedge per slice, with icons and selected-wedge art.
--- @param slices table
--- @param iconOffset number|nil extra radial icon offset (intro/outro animation)
--- @param hasTapOnly boolean|nil the menu has a tap-only quick action (it keeps the center)
function WheelMixin:SetSlices(slices, iconOffset, hasTapOnly)
    local count = #slices
    self.sliceCount = count
    self.iconRadiusExtra = GetIconRadius(count) - WEDGE_SPACING
    -- A lone slice has no direction to pick, so its icon sits in the center (where the quick
    -- action shows) instead of on a wedge, and a tap fires it; SetCenter swaps it with the cancel
    -- icon. Not when a tap-only quick action owns the center (Ring_Secure fires that on a tap).
    self.isSingleCentered = count == 1 and not hasTapOnly
    self.selectedIndex = nil
    -- With the lone slice in the center the background only shades around the center circle.
    if self.isSingleCentered ~= self.backgroundMasked then
        if self.isSingleCentered then
            self.Background:AddMaskTexture(self.BackgroundMask)
        else
            self.Background:RemoveMaskTexture(self.BackgroundMask)
        end
        self.backgroundMasked = self.isSingleCentered
    end
    self.Background:SetAlpha(self.isSingleCentered and SINGLE_BACKGROUND_ALPHA or 1)

    self:SetupFrameTexture(count)

    for i = 1, count do
        local wedge = self:GetWedge(i)
        local angle = GetSliceAngle(i, count)
        wedge.angle = angle

        wedge:ClearAllPoints()
        wedge:SetPoint("CENTER", self, "CENTER", cos(angle) * WEDGE_SPACING, sin(angle) * WEDGE_SPACING)
        SetupWedgeSelectedTexture(wedge, count, angle)

        Ring_Layout.SetIcon(wedge.Button.Icon, Ring_Actions.GetIcon(slices[i]))
        SetWedgeLabel(self, wedge, slices[i])
        self:SetWedgeSelected(wedge, false)
        wedge.Button:Show() -- SetCenter may have hidden it while this was a single-slice ring
        wedge:Show()
    end
    for i = count + 1, #self.Wedges do
        self.Wedges[i]:Hide()
        self.Wedges[i].Label:Hide()
    end

    self:PositionIcons(iconOffset or 0)

    -- Own copy: callers may pass a ring's stored slices, and SetSliceSlice replaces entries.
    self.slices = {}
    for i = 1, count do self.slices[i] = slices[i] end
    self:UpdateCooldowns()
    self:UpdateStates(true)
end


--- @param offset number extra radial offset for every icon (intro/outro animation)
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

--- Highlighted: wedge art, full-size icon and (with names on) the action's name.
function WheelMixin:SetWedgeSelected(wedge, selected)
    if self.isSingleCentered then
        -- In the center: the quick action, which shows no name.
        SetWedgeArtShown(wedge, false)
        wedge.Button:SetScale(SINGLE_ICON_SCALE)
        wedge.Label:Hide()
        return
    end
    SetWedgeArtShown(wedge, selected)
    wedge.Button:SetScale(selected and 1 or UNSELECTED_SCALE)
    wedge.Label:SetShown(selected and self.showLabels or false)
end

--- Highlights one slice (nil for none) and points the pointer at it.
function WheelMixin:SetSelection(index)
    if index == self.selectedIndex then return end
    if self.selectedIndex and self.Wedges[self.selectedIndex] then
        self:SetWedgeSelected(self.Wedges[self.selectedIndex], false)
    end
    if index then self:SetWedgeSelected(self.Wedges[index], true) end
    self.selectedIndex = index
end

--- @param angle number|nil radians; nil hides the pointer
function WheelMixin:SetPointerAngle(angle)
    if self.isSingleCentered then angle = nil end
    self.Pointer:SetShown(angle ~= nil)
    if angle then self.Pointer:SetRotation(angle) end
end

--- @param showQuick boolean show the quick action icon instead of the cancel icon
--- @param highlighted boolean show the cancel button's selected ring
function WheelMixin:SetCenter(showQuick, highlighted)
    if self.isSingleCentered then
        -- The slice's own icon is the quick action.
        self.Wedges[1].Button:SetShown(showQuick)
        self.Quick:Hide()
        self.CancelIcon:SetShown(not showQuick)
        self.CancelSelected:SetShown(highlighted)
    else
        self.Quick:SetShown(showQuick)
        self.CancelIcon:SetShown(not showQuick)
        self.CancelSelected:SetShown(highlighted)
    end
end

function WheelMixin:UpdateCooldowns()
    for i = 1, self.sliceCount or 0 do
        Ring_Layout.UpdateIconCooldown(self.Wedges[i].Button, self.slices[i])
    end
    Ring_Layout.UpdateIconCooldown(self.Quick, self.quickSlice)
end

--- Icon states (usable, in range, active; Ring_Layout.UpdateIconState): the in-game menu only,
--- which refreshes them while open (Ring_View). The settings preview keeps plain icons.
function WheelMixin:SetShowStates(shown)
    self.showStates = shown
end

--- @param fresh boolean|nil the icons were just given their slices (Ring_Layout.UpdateIconState)
function WheelMixin:UpdateStates(fresh)
    if not self.showStates then return end
    for i = 1, self.sliceCount or 0 do
        Ring_Layout.UpdateIconState(self.Wedges[i].Button, self.slices[i], fresh)
    end
    Ring_Layout.UpdateIconState(self.Quick, self.quickSlice, fresh)
end

--- Replaces what one wedge shows (a nested ring scrolled to another child slice).
function WheelMixin:SetSliceSlice(index, slice)
    local wedge = self.Wedges[index]
    if not (wedge and slice) then return end
    self.slices[index] = slice
    Ring_Layout.SetIcon(wedge.Button.Icon, Ring_Actions.GetIcon(slice))
    SetWedgeLabel(self, wedge, slice)
    Ring_Layout.UpdateIconCooldown(wedge.Button, slice)
    if self.showStates then Ring_Layout.UpdateIconState(wedge.Button, slice, true) end
end

--- The highlighted action's name beside its icon (the in-game menu, per the Show Action Names
--- setting; the preview uses tooltips instead). The center (quick action) shows none.
function WheelMixin:SetShowLabels(shown)
    self.showLabels = shown and true or false
end

--- Shows the center's selected ring. A single-slice ring always shows it: its center is the slice
--- (like the in-game ring, see Ring_View).
function WheelMixin:SetCenterHighlight(shown)
    self.CancelSelected:SetShown(shown or self.isSingleCentered or false)
end

--- @param icon number|string|nil
--- @param slice table|nil the slice the icon stands for, for its cooldown (nil for none)
function WheelMixin:SetQuickIcon(icon, slice)
    Ring_Layout.SetIcon(self.Quick.Icon, icon)
    self.quickSlice = slice
    Ring_Layout.UpdateIconCooldown(self.Quick, slice)
    if self.showStates then Ring_Layout.UpdateIconState(self.Quick, slice, true) end
end

function Ring_Layout.CreateWheel(parent, name)
    local wheel = CreateFrame("Frame", name, parent)
    wheel:SetSize(WHEEL_SIZE, WHEEL_SIZE)

    wheel.Background = wheel:CreateTexture(nil, "BACKGROUND", nil, 1)
    wheel.Background:SetPoint("CENTER")
    wheel.Background:SetAtlas(ATLAS_BACKGROUND, true)
    -- Added while a lone slice sits in the center (SetSlices).
    wheel.BackgroundMask = wheel:CreateMaskTexture()
    wheel.BackgroundMask:SetTexture(SINGLE_BACKGROUND_MASK_PATH:format(Path.Root), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    wheel.BackgroundMask:SetPoint("CENTER")
    local centerInfo = GetAtlasInfo(ATLAS_CANCEL_SELECTED)
    local maskSize = (centerInfo and centerInfo.width or 2 * DIVIDER_INNER_RADIUS) * SINGLE_BACKGROUND_MASK_SCALE
    wheel.BackgroundMask:SetSize(maskSize, maskSize)
    wheel.backgroundMasked = false

    wheel.Frame = wheel:CreateTexture(nil, "OVERLAY", nil, 1)
    wheel.Frame:SetPoint("CENTER")

    wheel.Pointer = wheel:CreateTexture(nil, "OVERLAY", nil, 2)
    wheel.Pointer:SetPoint("CENTER")
    wheel.Pointer:SetAtlas(ATLAS_POINTER, true)
    wheel.Pointer:Hide()

    wheel.CenterRing = wheel:CreateTexture(nil, "ARTWORK", nil, -1)
    wheel.CenterRing:SetPoint("CENTER")
    -- Blizzard's 4-slice frame art cropped to its center circle (its diagonal lines start at the
    -- circle's edge), so color, thickness and the clear center match the 4-slice wheel exactly.
    wheel.CenterRing:SetAtlas(ATLAS_FRAME:format(FALLBACK_WEDGE_COUNT), true)
    local cancelInfo = GetAtlasInfo(ATLAS_CANCEL_SELECTED)
    local circleRadius = (cancelInfo and cancelInfo.width / 2 or DIVIDER_INNER_RADIUS) - DIVIDER_INNER_OVERLAP + CENTER_RING_MASK_MARGIN
    wheel.CenterRingMask = wheel:CreateMaskTexture()
    wheel.CenterRingMask:SetPoint("CENTER")
    wheel.CenterRingMask:SetSize(circleRadius * 2, circleRadius * 2)
    wheel.CenterRingMask:SetTexture(CIRCLE_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    wheel.CenterRing:AddMaskTexture(wheel.CenterRingMask)
    wheel.CenterRing:Hide()

    -- Above the frame art (OVERLAY 1), whose center circle would otherwise dim it on 4-slice rings.
    -- Shares a sublevel with the pointer, which is hidden while this is shown.
    wheel.CancelSelected = wheel:CreateTexture(nil, "OVERLAY", nil, 2)
    wheel.CancelSelected:SetPoint("CENTER")
    wheel.CancelSelected:SetAtlas(ATLAS_CANCEL_SELECTED, true)

    wheel.CancelIcon = wheel:CreateTexture(nil, "OVERLAY", nil, 3)
    wheel.CancelIcon:SetPoint("CENTER")
    wheel.CancelIcon:SetAtlas(ATLAS_CANCEL_ICON, true)

    wheel.Quick = Ring_Layout.CreateActionIcon(wheel, QUICK_ICON_SIZE)
    -- Visibility badge for the quick action (settings preview only).
    wheel.QuickBadges = { Button = wheel.Quick }
    Private.CreateConditionBadge(wheel, wheel.QuickBadges)
    wheel.QuickBadges.ConditionBadge:SetScale(QUICK_BADGE_SCALE)
    wheel.Quick:SetPoint("CENTER")
    wheel.Quick:Hide()

    wheel.Wedges = {}
    wheel.Dividers = {}
    wheel.sliceCount = 0
    wheel.slices = {}

    -- Keep cooldowns current while the wheel is on screen.
    local events = CreateFrame("Frame", nil, wheel)
    for _, event in ipairs(Private.COOLDOWN_EVENTS) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function()
        if wheel:IsVisible() then wheel:UpdateCooldowns() end
    end)

    Mixin(wheel, WheelMixin)
    return wheel
end
