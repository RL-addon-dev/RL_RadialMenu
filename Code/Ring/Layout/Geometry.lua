--[[
    Ring_Layout: the wheel, one module over the files in this folder (Layout.xml), which share
    measurements and helpers through "@\\Ring\\Layout\\Private".
        Geometry.lua    this file, with where wedges, icons and names go, and shared measurements
        WedgeArt.lua    the art behind a highlighted wedge
        Wheel.lua       the wheel itself (CreateWheel and its methods)
        Badges.lua      the badges on an action icon's corners
        ActionIcon.lua  action icons, with their cooldowns, counts and states

    The wheel is modelled on Blizzard's RadialWheelFrameTemplate (the ping wheel,
    Blizzard_SharedXML/Blizzard_RadialWheel.xml and .lua). The in-game menu (Ring_View) and the
    settings preview (Setting/Rings) both draw it, so they look exactly the same.

    Wedges go clockwise from the top. Blizzard's go counter-clockwise, but ours must match the
    secure snippets' (Ring_Secure), which pick a wedge by the same angle math as GetSliceIndex.
]]

local env = select(2, ...)
local Ring_Layout = env.AX_Modules:New("@\\Ring\\Layout")
local Private = env.AX_Modules:New("@\\Ring\\Layout\\Private")

local GetAtlasInfo = C_Texture.GetAtlasInfo
local deg, atan2, floor, rad, sin, cos, pi = math.deg, math.atan2, math.floor, math.rad, math.sin, math.cos, math.pi
local TWO_PI = 2 * pi

-- Menus with many actions push their icons outward, so neighbours keep this much distance between
-- their centers (an icon plus a gap). Only the icons move, and the wedge art stays at WEDGE_SPACING.
local ICON_MIN_SPACING = 58
local ICON_MAX_RADIUS  = 140

-- The center circle's radius, when its atlas is missing.
local CENTER_RADIUS_FALLBACK = 28
-- The center circle's atlas has transparent padding around the visible circle. Dividers and the
-- custom wedge art start this far inside its edge, and are drawn under the center ring, so they
-- meet it without a gap.
local DIVIDER_INNER_OVERLAP = 3

-- Placing things beside an action, away from the wheel center (action names, the preview's
-- tooltips). An axis counts once the direction's component passes this. It's sin 22.5 degrees,
-- so each of the 8 directions covers 45 degrees.
local OUTWARD_AXIS_THRESHOLD = 0.38
local OPPOSITE_POINT = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT", [""] = "" }



-- Shared by the files

Private.ATLAS_CANCEL_SELECTED = "Radial_Wheel_Select_Close" -- the center circle's selected ring
Private.FALLBACK_WEDGE_COUNT = 4 -- the ping wheel's own count, whose art is assumed to always exist
Private.WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- Blizzard's values (the large wheel).
Private.WEDGE_SPACING = 80 -- from the wheel center to a wedge's center
Private.WEDGE_SELECTED_SPACING = 20 -- how much further out the highlight art sits

--- Whether this client has atlas `name`.
---@param name string
---@return boolean
function Private.HasAtlas(name)
    return GetAtlasInfo(name) ~= nil
end

--- The center circle's radius: half of Blizzard's selected center art.
---@return number
function Private.GetCenterRadius()
    local info = GetAtlasInfo(Private.ATLAS_CANCEL_SELECTED)
    return (info and info.width / 2) or CENTER_RADIUS_FALLBACK
end

--- Where dividers and wedge art start from the wheel center: just inside the center circle.
---@return number
function Private.GetDividerStartRadius()
    return Private.GetCenterRadius() - DIVIDER_INNER_OVERLAP
end



-- Geometry

--- The wedge (1 to `count`) the direction (`dx`, `dy`) points at, or nil inside the dead zone. The
--- secure snippets use the same math (Ring_Secure).
---@param dx number
---@param dy number
---@param count integer
---@param deadzone number
---@return integer?
function Ring_Layout.GetSliceIndex(dx, dy, count, deadzone)
    if count == 0 or dx * dx + dy * dy <= deadzone * deadzone then return nil end
    local step = 360 / count
    local offset = (90 - deg(atan2(dy, dx))) % 360
    return floor((offset + step / 2) / step) % count + 1
end

--- The middle of wedge `index` of `count`, in radians counter-clockwise from +x (the convention
--- SetRotation uses).
---@param index integer
---@param count integer
---@return number
function Ring_Layout.GetSliceAngle(index, count)
    return (rad(90 - (index - 1) * 360 / count)) % TWO_PI
end

--- The boundary after wedge `index` of `count`, going clockwise, in radians.
---@param index integer
---@param count integer
---@return number
function Ring_Layout.GetBoundaryAngle(index, count)
    return Ring_Layout.GetSliceAngle(index, count) - pi / count
end

--- How far the action icons sit from the wheel center: Blizzard's spacing, or further out when the
--- actions would otherwise crowd each other.
---@param count integer
---@return number
function Ring_Layout.GetIconRadius(count)
    if count < 3 then return Private.WEDGE_SPACING end
    local needed = ICON_MIN_SPACING / (2 * sin(pi / count)) -- the chord between neighbours
    return math.min(math.max(Private.WEDGE_SPACING, needed), ICON_MAX_RADIUS)
end

--- Anchor points to put something beside `owner`, away from the wheel center along `angle`
--- (radians, counter-clockwise from +x). For example, above a top action, or to the right of a
--- right one.
---@param angle number
---@return string point the placed frame's point (its side facing the owner)
---@return string ownerPoint the owner's point it touches (the owner's outer side)
function Ring_Layout.GetOutwardPoints(angle)
    local c, s = cos(angle), sin(angle)
    local vertical = (s > OUTWARD_AXIS_THRESHOLD and "TOP") or (s < -OUTWARD_AXIS_THRESHOLD and "BOTTOM") or ""
    local horizontal = (c > OUTWARD_AXIS_THRESHOLD and "RIGHT") or (c < -OUTWARD_AXIS_THRESHOLD and "LEFT") or ""
    local ownerPoint = vertical .. horizontal
    local point = OPPOSITE_POINT[vertical] .. OPPOSITE_POINT[horizontal]
    return point ~= "" and point or "CENTER", ownerPoint ~= "" and ownerPoint or "CENTER"
end
