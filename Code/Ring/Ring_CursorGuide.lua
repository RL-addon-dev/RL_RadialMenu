--[[
    Cursor guide (fixed position, optional): a faint outline of the gesture drawn at the key-down
    cursor spot, since that's where a fixed menu is steered from. Shown by Ring_View while a menu
    is open (Ring_CursorGuide.Frame: Setup, Update, and the usual frame methods).
]]

local env = select(2, ...)
local Config = env.Config
local Ring_Layout = env.AX_Modules:Import("@\\Ring\\Layout")
local Ring_CursorGuide = env.AX_Modules:New("@\\Ring\\CursorGuide")

-- Drawn at gesture scale (the dead zone in UI units, not Menu Size), so its lines are exactly
-- where the gesture's boundaries are.
local GUIDE_CIRCLE_SEGMENTS = 48
local GUIDE_DIVIDER_LENGTH = 14 -- past the dead zone
local GUIDE_POINTER_LENGTH = 9
local GUIDE_THICKNESS = 2
-- Color from the Cursor Guide Color setting; faint normally, brighter for the selected slice.
local GUIDE_ALPHA = 0.25
local GUIDE_ACTIVE_ALPHA = 0.7
local GUIDE_COLOR = { 1, 1, 1, GUIDE_ALPHA }
local GUIDE_ACTIVE_COLOR = { 1, 1, 1, GUIDE_ACTIVE_ALPHA }
-- Quick action square (Distance to Cancel Quick Action): filled while a release would fire the
-- quick action, hollow once the cursor has left it (a release in the center cancels) or when
-- there's no quick action.
local GUIDE_NUDGE_MIN_SIZE = 5
local GUIDE_NUDGE_EDGE = 2

local Guide = CreateFrame("Frame", "RLRM_CursorGuide", UIParent)
Guide:SetFrameStrata("FULLSCREEN_DIALOG")
Guide:SetSize(1, 1)
Guide:Hide()
Guide.Circle, Guide.Dividers = {}, {}

local function GuideLine(color)
    local line = Guide:CreateLine(nil, "OVERLAY")
    line:SetThickness(GUIDE_THICKNESS)
    line:SetColorTexture(unpack(color))
    return line
end

--- Line from `inner` to `outer` along `angle` (radians), from the guide's center.
local function PlaceRadial(line, angle, inner, outer)
    local c, s = math.cos(angle), math.sin(angle)
    line:SetStartPoint("CENTER", Guide, c * inner, s * inner)
    line:SetEndPoint("CENTER", Guide, c * outer, s * outer)
end

for i = 1, GUIDE_CIRCLE_SEGMENTS do Guide.Circle[i] = GuideLine(GUIDE_COLOR) end
Guide.Pointer = GuideLine(GUIDE_ACTIVE_COLOR)

-- Quick action square: a fill plus four edges (so it can be drawn hollow).
Guide.NudgeFill = Guide:CreateTexture(nil, "OVERLAY")
Guide.NudgeFill:SetPoint("CENTER")
Guide.NudgeEdges = {}
for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local edge = Guide:CreateTexture(nil, "OVERLAY")
    edge.side = side
    Guide.NudgeEdges[#Guide.NudgeEdges + 1] = edge
end

--- Sizes the quick action square (`size` px: the real probe's side, but at least the minimum).
local function SetupNudge(size)
    size = math.max(size, GUIDE_NUDGE_MIN_SIZE)
    local half = size / 2
    Guide.NudgeFill:SetSize(size, size)
    for _, edge in ipairs(Guide.NudgeEdges) do
        edge:ClearAllPoints()
        if edge.side == "TOP" or edge.side == "BOTTOM" then
            edge:SetSize(size, GUIDE_NUDGE_EDGE)
            edge:SetPoint("CENTER", Guide, "CENTER", 0, (edge.side == "TOP" and 1 or -1) * (half - GUIDE_NUDGE_EDGE / 2))
        else
            edge:SetSize(GUIDE_NUDGE_EDGE, size)
            edge:SetPoint("CENTER", Guide, "CENTER", (edge.side == "RIGHT" and 1 or -1) * (half - GUIDE_NUDGE_EDGE / 2), 0)
        end
    end
end

--- Filled (bright) while a release fires the quick action; hollow (dim) otherwise.
local function SetNudgeArmed(armed)
    Guide.NudgeFill:SetShown(armed)
    Guide.NudgeFill:SetColorTexture(unpack(GUIDE_ACTIVE_COLOR))
    for _, edge in ipairs(Guide.NudgeEdges) do
        edge:SetColorTexture(unpack(armed and GUIDE_ACTIVE_COLOR or GUIDE_COLOR))
    end
end

--- Lays the guide out for `count` slices, dead zone radius `deadzone`, quick action square side
--- `probeSize`; `hasQuick` = a tap fires something (else the center only cancels).
function Guide:Setup(count, deadzone, probeSize, hasQuick)
    -- Current color (the setting can change between openings).
    local color = Config.DBGlobal:GetVariable("CursorGuideColor") or {}
    local r, g, b = color.r or 1, color.g or 1, color.b or 1
    GUIDE_COLOR[1], GUIDE_COLOR[2], GUIDE_COLOR[3] = r, g, b
    GUIDE_ACTIVE_COLOR[1], GUIDE_ACTIVE_COLOR[2], GUIDE_ACTIVE_COLOR[3] = r, g, b
    for _, line in ipairs(self.Circle) do line:SetColorTexture(unpack(GUIDE_COLOR)) end
    self.Pointer:SetColorTexture(unpack(GUIDE_ACTIVE_COLOR))

    local step = 2 * math.pi / GUIDE_CIRCLE_SEGMENTS
    for i, line in ipairs(self.Circle) do
        local a0, a1 = (i - 1) * step, i * step
        line:SetStartPoint("CENTER", self, math.cos(a0) * deadzone, math.sin(a0) * deadzone)
        line:SetEndPoint("CENTER", self, math.cos(a1) * deadzone, math.sin(a1) * deadzone)
    end

    -- Boundary after slice i, clockwise (as Ring_Layout draws its dividers). One slice: none.
    local dividers = count >= 2 and count or 0
    for i = 1, dividers do
        local line = self.Dividers[i] or GuideLine(GUIDE_COLOR)
        self.Dividers[i] = line
        PlaceRadial(line, Ring_Layout.GetSliceAngle(i, count) - math.pi / count, deadzone, deadzone + GUIDE_DIVIDER_LENGTH)
        line:SetColorTexture(unpack(GUIDE_COLOR))
        line:Show()
    end
    for i = dividers + 1, #self.Dividers do self.Dividers[i]:Hide() end

    self.count, self.deadzone, self.selected = dividers, deadzone, nil
    self.Pointer:Hide()

    SetupNudge(probeSize)
    self.hasQuick, self.armed = hasQuick, hasQuick
    SetNudgeArmed(hasQuick)
end

--- Brightens the selected slice's two boundaries, points at the cursor's direction, and shows
--- whether the cursor has left the quick action square (`moved`).
function Guide:Update(index, angle, moved)
    local armed = self.hasQuick and not moved
    if armed ~= self.armed then
        self.armed = armed
        SetNudgeArmed(armed)
    end
    if index ~= self.selected then
        self.selected = index
        for i = 1, self.count do
            local active = index and (i == index or i == (index - 2) % self.count + 1)
            self.Dividers[i]:SetColorTexture(unpack(active and GUIDE_ACTIVE_COLOR or GUIDE_COLOR))
        end
    end
    self.Pointer:SetShown(angle ~= nil)
    if angle then PlaceRadial(self.Pointer, angle, self.deadzone, self.deadzone + GUIDE_POINTER_LENGTH) end
end

Ring_CursorGuide.Frame = Guide
