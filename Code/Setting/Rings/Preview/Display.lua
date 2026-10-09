--[[
    Settings preview: what it shows. The selected slice (and its X), the drop / drag target
    (gold wedge, gold divider line, center highlight) with a label tooltip pointing out of the
    wheel, the "+" on a hovered gap, and the slice / center tooltips. See Preview.lua.
]]

local env = select(2, ...)
local L = env.L
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Layout = env.AX_Modules:Await("@\\Ring\\Layout")
local Ring_Live = env.AX_Modules:Await("@\\Ring\\Live")
local Rings_Preview = env.AX_Modules:Import("@\\Setting\\Rings\\Preview")
local Private = env.AX_Modules:Import("@\\Setting\\Rings\\Preview\\Private")

local atan2, cos, sin, pi = math.atan2, math.cos, math.sin, math.pi
local PreviewMixin = Private.PreviewMixin
local GAP_BUTTON_RADIUS = Private.GAP_BUTTON_RADIUS

local INSERT_LINE_INNER = 30
local INSERT_LINE_OUTER = 150
local GAP_BUTTON_ICON_CLEARANCE = 48 -- keeps the "+" outside icons pushed out on crowded rings
local EMPTY_BUTTON_GAP = 8 -- empty ring: "+" just below the "no slices yet" text
-- Tooltips open away from the wheel center (Ring_Layout.GetOutwardPoints), this far out.
local TOOLTIP_GAP = 6



--- Opens GameTooltip on `owner`, placed away from the wheel center along `angle` (radians,
--- counter-clockwise from +x): top slices get it above, right slices to the right, and so on.
local function SetTooltipOutward(owner, angle)
    local c, s = cos(angle), sin(angle)
    -- The tooltip's opposite corner / edge touches the owner's outer corner / edge (the same
    -- rule places the in-game menu's action names).
    local tooltipPoint, ownerPoint = Ring_Layout.GetOutwardPoints(angle)

    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint(tooltipPoint, owner, ownerPoint, c * TOOLTIP_GAP, s * TOOLTIP_GAP)
end
Private.SetTooltipOutward = SetTooltipOutward
Rings_Preview.SetTooltipOutward = SetTooltipOutward


-- Drop / drag target

--- Shows what releasing now would do: gold wedge over a slice, a gold divider line between two,
--- the center highlight for the center, plus a label at the cursor.
--- @param from number|nil the slice being reordered (nil for a drop from the game)
function PreviewMixin:ShowTarget(target, from, dx, dy)
    local wheel = self.wheel
    local label, lineAngle, detail
    -- Where the label tooltip points from: the slice, the divider, or the center (downwards).
    local owner, ownerAngle

    if target.mode == "over" then
        local wedge = wheel.Wedges[target.index]
        owner, ownerAngle = wedge and wedge.Button, wedge and wedge.angle
        self:SetSelected(target.index, false)
        if from and from ~= "quick" then
            label = target.index ~= from and L["Config - Rings - Drag - Swap"] or nil
        else
            label = L["Config - Rings - Drag - Replace"]
        end
    elseif target.mode == "between" then
        self:SetSelected(nil)
        -- Moving next to itself changes nothing, so don't advertise it.
        local noop = from and from ~= "quick" and (target.index == from or target.index == from + 1
            or (from == wheel.sliceCount and target.index == 1))
        if not noop then
            lineAngle = target.angle
            label = (from and from ~= "quick") and L["Config - Rings - Drag - Move"] or L["Config - Rings - Drag - Insert"]
            owner, ownerAngle = self:PlaceLabelAnchor(target.angle, self:GetGapRadius()), target.angle
        end
    elseif target.mode == "add" then
        self:SetSelected(nil)
        label = L["Config - Rings - Drag - Add"]
        owner, ownerAngle = self:PlaceLabelAnchor(-pi / 2, 0), -pi / 2
    else
        -- Center: sets the quick action (nothing to do when dragging the quick action itself).
        self:SetSelected(nil)
        -- Nested rings and action bars can't be the quick action: say so, and what to do instead.
        local fromSlice = type(from) == "number" and self.ring and self:GetSlice(from)
        if fromSlice and not Ring_Data.CanBeQuickAction(fromSlice) then
            label, detail = L["Config - Rings - Drag - QuickRing"], L["Config - Rings - Drag - QuickRing - Hint"]
        elseif from ~= "quick" then
            label = L["Config - Rings - Drag - Quick"]
        end
        owner, ownerAngle = self:PlaceLabelAnchor(-pi / 2, 0), -pi / 2
    end

    wheel:SetPointerAngle((target.mode == "over" or target.mode == "between") and atan2(dy, dx) or nil)
    wheel:SetCenterHighlight(target.mode == "center")

    self.InsertLine:SetShown(lineAngle ~= nil)
    if lineAngle then
        local c, s = cos(lineAngle), sin(lineAngle)
        self.InsertLine:SetStartPoint("CENTER", wheel, c * INSERT_LINE_INNER, s * INSERT_LINE_INNER)
        self.InsertLine:SetEndPoint("CENTER", wheel, c * INSERT_LINE_OUTER, s * INSERT_LINE_OUTER)
    end

    self:SetDragLabel(label, owner, ownerAngle, detail)
end

--- Radius of the "+" on a gap (outside the icons, pushed out on crowded rings).
function PreviewMixin:GetGapRadius()
    return math.max(GAP_BUTTON_RADIUS, Ring_Layout.GetIconRadius(self.wheel.sliceCount) + GAP_BUTTON_ICON_CLEARANCE)
end

--- Moves the invisible label anchor to `radius` along `angle` (0 = the wheel center).
function PreviewMixin:PlaceLabelAnchor(angle, radius)
    local anchor = self.LabelAnchor
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", self.wheel, "CENTER", cos(angle) * radius, sin(angle) * radius)
    return anchor
end

--- What releasing would do, as a standard GameTooltip pointing out of the wheel from `owner`.
--- @param detail string|nil a second, wrapped line under the label
function PreviewMixin:SetDragLabel(text, owner, angle, detail)
    if not (text and owner) then
        if self.labelOwner and GameTooltip:GetOwner() == self.labelOwner then GameTooltip:Hide() end
        self.labelOwner, self.labelText, self.labelAngle = nil, nil, nil
        return
    end
    -- Called every frame while dragging: only re-anchor when something changed.
    if owner == self.labelOwner and text == self.labelText and angle == self.labelAngle
        and GameTooltip:GetOwner() == owner and GameTooltip:IsShown() then
        return
    end
    self.labelOwner, self.labelText, self.labelAngle = owner, text, angle
    SetTooltipOutward(owner, angle)
    GameTooltip:SetText(text, 1, 1, 1)
    if detail then GameTooltip:AddLine(detail, nil, nil, nil, true) end
    GameTooltip:Show()
end

function PreviewMixin:HideTarget()
    self.InsertLine:Hide()
    self:SetDragLabel(nil)
end

--- Shows the "+" on a "between" target's divider. With no target it hides, except on an empty
--- ring, where it always sits where the first slice will go.
function PreviewMixin:SetGapTarget(target)
    local button = self.GapButton
    button:ClearAllPoints()
    if self.readOnly then
        button:Hide()
        return
    end

    if target then
        button.insertIndex = target.index
        button.tooltipAngle = target.angle
        local radius = self:GetGapRadius()
        button:SetPoint("CENTER", self.wheel, "CENTER", cos(target.angle) * radius, sin(target.angle) * radius)
        button:Show()
    elseif self.ring and #self.shown == 0 then
        button.insertIndex = nil
        button.tooltipAngle = -pi / 2 -- below the wheel center: tooltip opens downwards
        button:SetPoint("TOP", self.Empty, "BOTTOM", 0, -EMPTY_BUTTON_GAP)
        button:Show()
    else
        button:Hide()
    end
end



-- Selection / tooltip

--- @param showRemove boolean|nil show the X on the selected slice (default true)
function PreviewMixin:SetSelected(index, showRemove)
    local wheel = self.wheel
    if index ~= self.selectedIndex then
        local previous = self.selectedIndex and wheel.Wedges[self.selectedIndex]
        if previous and previous.RemoveButton then previous.RemoveButton:Hide() end
        self.selectedIndex = index
        wheel:SetSelection(index)
    end

    local wedge = index and wheel.Wedges[index]
    if wedge then wedge.RemoveButton:SetShown(showRemove ~= false) end
end


--- The tooltip's Visibility group for `slice` (after an empty line), if it can hide.
local function AddVisibilityGroup(slice)
    local condition = slice and Ring_Actions.GetVisibilityCondition(slice)
    if not condition then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Config - Rings - Tooltip - Visibility"] .. " " .. L["Config - Rings - Visibility - " .. condition], nil, nil, nil, true)
    if not Ring_Actions.IsSliceAvailable(slice) then
        GameTooltip:AddLine(L["Config - Rings - Visibility - HiddenNow"], 1, 0.5, 0.25, true)
    end
end

function PreviewMixin:SetTooltipIndex(index)
    if index == self.tooltipIndex then return end
    self.tooltipIndex = index

    if index == "center" then
        self:ShowCenterTooltip()
        return
    end

    local slice = index and self.ring and self:GetSlice(index)
    local wedge = index and self.wheel.Wedges[index]
    if not (slice and wedge) then
        if self.tooltipOwner and GameTooltip:GetOwner() == self.tooltipOwner then GameTooltip:Hide() end
        self.tooltipOwner = nil
        return
    end

    self.tooltipOwner = wedge.Button
    SetTooltipOutward(wedge.Button, wedge.angle)
    GameTooltip:SetText(Ring_Actions.GetLabel(slice), 1, 1, 1)

    -- Groups under the name, each after an empty line: Control, Nested ring, Visibility.
    local function Group(text, r, g, b)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(text, r, g, b, true)
    end
    local control = L["Config - Rings - Preview - Control"]
    if slice.kind == "ring" then
        control = control .. " " .. (slice.expand and L["Config - Rings - Preview - Control - ToScroll"] or L["Config - Rings - Preview - Control - ToExpand"])
    end
    Group(L["Config - Rings - Tooltip - Control"] .. " " .. control)
    if slice.kind == "ring" then
        local nest = slice.expand and L["Config - Rings - Nest - Expand"] or L["Config - Rings - Nest - Description"]
        -- A scroll list is flat: say so when this submenu has submenus of its own.
        if not slice.expand and Ring_Live.HasSubmenus(slice.ring) then
            nest = nest .. " " .. L["Config - Rings - Nest - Flatten"]
        end
        Group(nest)
    end
    AddVisibilityGroup(slice)
    GameTooltip:Show()
end

--- The quick action's stored slice: the tap-only slice or one of the ring's slices (nil for None
--- or Last Used Slice).
function PreviewMixin:GetQuickStoredSlice()
    local ring = self.ring
    if not ring or ring.quickAction == Ring_Data.QuickAction.Last then return nil end
    return Ring_Data.GetQuickActionSlice(ring)
end

--- Tooltip for the center: the current quick action and how to change it from the wheel.
function PreviewMixin:ShowCenterTooltip()
    local ring = self.ring
    if not ring then return end
    local owner = self:PlaceLabelAnchor(-pi / 2, 0)
    self.tooltipOwner = owner
    SetTooltipOutward(owner, -pi / 2)

    local title
    if ring.quickAction == Ring_Data.QuickAction.Last then
        title = L["Config - Rings - QuickAction - Last"]
    else
        local slice = Ring_Data.GetQuickActionSlice(ring)
        title = slice and Ring_Actions.GetLabel(slice) or L["Config - Rings - QuickAction - None"]
    end
    GameTooltip:SetText(format(L["Config - Rings - Tooltip - QuickTitle"], title), 1, 1, 1)

    local tapOnly = ring.quickAction == Ring_Data.QuickAction.Custom and ring.quickSlice
    if tapOnly then
        GameTooltip:AddLine(L["Config - Rings - Tooltip - TapOnly"], nil, nil, nil, true)
    end
    GameTooltip:AddLine(" ")
    local control = self.readOnly and L["Config - Rings - Preview - Control - QuickReadOnly"] or L["Config - Rings - Preview - Control - Quick"]
    -- With a slice as the quick action, a double-click does nothing (the X clears it).
    if self:GetQuickStoredSlice() then
        control = self.readOnly and L["Config - Rings - Preview - Control - QuickSetReadOnly"] or L["Config - Rings - Preview - Control - QuickSet"]
    end
    if tapOnly and not self.readOnly then
        control = control .. " " .. L["Config - Rings - Preview - Control - QuickToWheel"]
    end
    if self:GetQuickStoredSlice() then
        control = control .. " " .. L["Config - Rings - Preview - Control - QuickClear"]
    end
    GameTooltip:AddLine(L["Config - Rings - Tooltip - Control"] .. " " .. control, nil, nil, nil, true)

    -- Same group as a slice's tooltip, for the quick action's slice.
    AddVisibilityGroup(self:GetQuickStoredSlice())
    GameTooltip:Show()
end

function PreviewMixin:ClearInteraction()
    self.QuickRemove:Hide()
    self:SetSelected(nil)
    self:SetTooltipIndex(nil)
    self:HideTarget()
    self:SetGapTarget(nil)
    self.wheel:SetPointerAngle(nil)
    self.wheel:SetCenterHighlight(false)
end
