--[[
    Menus_Preview (see Preview.lua): what the preview shows. That's the selected action (and its
    X), the drop or drag target (gold wedge, gold divider line, center highlight) with a label
    tooltip pointing out of the wheel, the "+" on a hovered gap, and the action and center
    tooltips.
]]

local env = select(2, ...)
local L = env.L
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Menu_Layout = env.AX_Modules:Await("@\\Menu\\Layout")
local Menu_Live = env.AX_Modules:Await("@\\Menu\\Live")
local Private = env.AX_Modules:Import("@\\Setting\\Menus\\Preview\\Private")
local Menu_Kinds = env.AX_Modules:Await("@\\Menu\\Kinds")
local Utils_ConsolePort = env.AX_Modules:Import("@\\Utils\\ConsolePort")

local atan2, cos, sin = math.atan2, math.cos, math.sin

---@class MenuPreview
local PreviewMixin = Private.PreviewMixin

local INSERT_LINE_INNER = 30
local INSERT_LINE_OUTER = 150
local GAP_BUTTON_ICON_CLEARANCE = 48 -- keeps the "+" outside icons pushed out on crowded menus
local EMPTY_BUTTON_GAP = 8 -- on an empty menu, the "+" sits just below the "no actions yet" text
-- Tooltips open away from the wheel center (Menu_Layout.GetOutwardPoints), this far out.
local TOOLTIP_GAP = 6
local NOTE_COLOR = { 1, 0.5, 0.25 } -- orange, for "hidden now" and whose a menu is



--- Opens GameTooltip on `owner`, placed away from the wheel center along `angle` (radians,
--- counter-clockwise from +x). Top actions get it above, right actions to the right, and so on.
---@param owner Frame
---@param angle number
function Private.SetTooltipOutward(owner, angle)
    local c, s = cos(angle), sin(angle)
    -- The tooltip's opposite corner or edge touches the owner's outer corner or edge (the same
    -- rule places the in-game menu's action names).
    local tooltipPoint, ownerPoint = Menu_Layout.GetOutwardPoints(angle)

    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint(tooltipPoint, owner, ownerPoint, c * TOOLTIP_GAP, s * TOOLTIP_GAP)
end


-- Drop and drag target


--- Shows what releasing now would do: a gold wedge over an action, a gold divider line between
--- two, the center highlight for the center, plus a label at the cursor.
---@param target table GetDropTarget's
---@param from integer|string|nil the wedge being reordered, Private.QUICK, or nil for a drop from
---     the game
---@param dx number
---@param dy number
function PreviewMixin:ShowTarget(target, from, dx, dy)
    local wheel = self.wheel
    local label, lineAngle, detail
    -- Where the label tooltip points from: the action, the divider, or the center (downwards).
    local owner, ownerAngle

    if target.mode == Private.Target.Over then
        local wedge = wheel.Wedges[target.index]
        owner, ownerAngle = wedge and wedge.Button, wedge and wedge.angle
        self:SetSelected(target.index, false)
        if from and from ~= Private.QUICK then
            label = target.index ~= from and L["Config - Menus - Drag - Swap"] or nil
        elseif from == Private.QUICK then
            -- The center's action and this one swap. A submenu or action bar can't go to the center.
            local over = self.menu and self:GetAction(target.index)
            if over and not Menu_Data.CanBeQuickAction(over) then
                label, detail = L["Config - Menus - Drag - QuickMenu"], L["Config - Menus - Drag - QuickSwapMenu - Hint"]
            else
                label = L["Config - Menus - Drag - Swap"]
            end
        else
            label = L["Config - Menus - Drag - Replace"]
        end
    elseif target.mode == Private.Target.Between then
        self:SetSelected(nil)
        -- Moving next to itself changes nothing, so it isn't offered.
        local noop = from and from ~= Private.QUICK and (target.index == from or target.index == from + 1
            or (from == wheel.actionCount and target.index == 1))
        if not noop then
            lineAngle = target.angle
            local moving = from and from ~= Private.QUICK
            label = moving and L["Config - Menus - Drag - Move"] or L["Config - Menus - Drag - Insert"]
            owner, ownerAngle = self:PlaceLabelAnchor(target.angle, self:GetGapRadius()), target.angle
        end
    elseif target.mode == Private.Target.Add then
        self:SetSelected(nil)
        label = L["Config - Menus - Drag - Add"]
        owner, ownerAngle = self:PlaceLabelAnchor(Private.BELOW, 0), Private.BELOW
    else
        -- The center sets the quick action (nothing to do when dragging the quick action itself).
        self:SetSelected(nil)
        -- Submenus and action bars can't be the quick action, so it says so, and what to do instead.
        local fromAction = type(from) == "number" and self.menu and self:GetAction(from)
        if fromAction and not Menu_Data.CanBeQuickAction(fromAction) then
            label, detail = L["Config - Menus - Drag - QuickMenu"], L["Config - Menus - Drag - QuickMenu - Hint"]
        elseif from ~= Private.QUICK then
            label = L["Config - Menus - Drag - Quick"]
        end
        owner, ownerAngle = self:PlaceLabelAnchor(Private.BELOW, 0), Private.BELOW
    end

    local onWedges = target.mode == Private.Target.Over or target.mode == Private.Target.Between
    wheel:SetPointerAngle(onWedges and atan2(dy, dx) or nil)
    wheel:SetCenterHighlight(target.mode == Private.Target.Center)

    self.InsertLine:SetShown(lineAngle ~= nil)
    if lineAngle then
        local c, s = cos(lineAngle), sin(lineAngle)
        self.InsertLine:SetStartPoint("CENTER", wheel, c * INSERT_LINE_INNER, s * INSERT_LINE_INNER)
        self.InsertLine:SetEndPoint("CENTER", wheel, c * INSERT_LINE_OUTER, s * INSERT_LINE_OUTER)
    end

    self:SetDragLabel(label, owner, ownerAngle, detail)
end

--- The radius of the "+" on a gap (outside the icons, pushed out on crowded menus).
---@return number
function PreviewMixin:GetGapRadius()
    local outsideIcons = Menu_Layout.GetIconRadius(self.wheel.actionCount) + GAP_BUTTON_ICON_CLEARANCE
    return math.max(Private.GAP_BUTTON_RADIUS, outsideIcons)
end

--- Moves the invisible label anchor to `radius` along `angle` (a radius of 0 is the wheel center).
---@param angle number
---@param radius number
---@return Frame
function PreviewMixin:PlaceLabelAnchor(angle, radius)
    local anchor = self.LabelAnchor
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", self.wheel, "CENTER", cos(angle) * radius, sin(angle) * radius)
    return anchor
end

--- What releasing would do, as a standard GameTooltip pointing out of the wheel from `owner`.
---@param text string? nil hides it
---@param owner Frame?
---@param angle number?
---@param detail string? a second, wrapped line under the label
function PreviewMixin:SetDragLabel(text, owner, angle, detail)
    if not (text and owner) then
        if self.labelOwner and GameTooltip:GetOwner() == self.labelOwner then GameTooltip:Hide() end
        self.labelOwner, self.labelText, self.labelAngle = nil, nil, nil
        return
    end
    -- It's called every frame while dragging, so it only anchors again when something changed.
    if owner == self.labelOwner and text == self.labelText and angle == self.labelAngle
        and GameTooltip:GetOwner() == owner and GameTooltip:IsShown() then
        return
    end
    self.labelOwner, self.labelText, self.labelAngle = owner, text, angle
    Private.SetTooltipOutward(owner, angle --[[@as number]])
    GameTooltip:SetText(text, 1, 1, 1)
    if detail then GameTooltip:AddLine(detail, nil, nil, nil, true) end
    GameTooltip:Show()
end

--- Hides the drop target's line and label.
function PreviewMixin:HideTarget()
    self.InsertLine:Hide()
    self:SetDragLabel(nil)
end

--- Shows the "+" on a between target's divider. With no target it hides, except on an empty
--- menu, where it always sits where the first action will go.
---@param target table? a GetDropTarget of Private.Target.Between
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
    elseif self.menu and #self.shown == 0 then
        button.insertIndex = nil
        button.tooltipAngle = Private.BELOW -- below the wheel center, so its tooltip opens downwards
        button:SetPoint("TOP", self.Empty, "BOTTOM", 0, -EMPTY_BUTTON_GAP)
        button:Show()
    else
        button:Hide()
    end
end



-- Selection and tooltips

--- Selects wedge `index` (nil for none).
---@param index integer?
---@param showRemove boolean? show the X on the selected action (true by default)
function PreviewMixin:SetSelected(index, showRemove)
    local wheel = self.wheel
    if index ~= self.selectedIndex then
        local previous = self.selectedIndex and wheel.Wedges[self.selectedIndex]
        if previous and previous.RemoveButton then previous.RemoveButton:Hide() end
        self.selectedIndex = index
        wheel:SetSelection(index)
    end

    local wedge = index and wheel.Wedges[index]
    if wedge then wedge.RemoveButton:SetShown(showRemove ~= false and not self.locked) end
end


--- The tooltip's Visibility group for `action` (after an empty line), if it can hide.
---@param action Action?
local function AddVisibilityGroup(action)
    local condition = action and Menu_Actions.GetVisibilityCondition(action)
    if not condition then return end
    GameTooltip:AddLine(" ")
    -- "Config - Menus - Visibility - <condition>", one per visibility condition (KindDefinition.condition).
    GameTooltip:AddLine(L["Config - Menus - Tooltip - Visibility"] .. " " .. L["Config - Menus - Visibility - " .. condition], nil, nil, nil, true)
    if not Menu_Actions.IsActionAvailable(action) then
        GameTooltip:AddLine(L["Config - Menus - Visibility - HiddenNow"],
            NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true)
    end
end

--- Shows the tooltip of wedge `index` or of the center (Private.CENTER), or hides it with nil.
---@param index integer|string|nil
function PreviewMixin:SetTooltipIndex(index)
    if index == self.tooltipIndex then return end
    self.tooltipIndex = index

    if index == Private.CENTER then
        self:ShowCenterTooltip()
        return
    end

    local action = index and self.menu and self:GetAction(index --[[@as integer]])
    local wedge = index and self.wheel.Wedges[index]
    if not (action and wedge) then
        if self.tooltipOwner and GameTooltip:GetOwner() == self.tooltipOwner then GameTooltip:Hide() end
        self.tooltipOwner = nil
        return
    end

    self.tooltipOwner = wedge.Button
    Private.SetTooltipOutward(wedge.Button, wedge.angle)
    GameTooltip:SetText(Menu_Actions.GetLabel(action), 1, 1, 1)

    -- Groups under the name, each after an empty line: Control, Submenu, Visibility.
    local function Group(text, r, g, b)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(text, r, g, b, true)
    end
    local control = L["Config - Menus - Preview - Control"]
    if action.kind == Menu_Kinds.Kind.Submenu then
        control = control .. " " .. (action.spread and L["Config - Menus - Preview - Control - ToScroll"] or L["Config - Menus - Preview - Control - ToSpread"])
    end
    Group(L["Config - Menus - Tooltip - Control"] .. " " .. control)
    if action.kind == Menu_Kinds.Kind.Submenu then
        -- With a controller, the D-pad scrolls it instead of the mouse wheel.
        local controller = env.IsGamepadUI() or Utils_ConsolePort.IsActive()
        local submenuText = action.spread and L["Config - Menus - Submenu - Spread"]
            or L["Config - Menus - Submenu - Description" .. (controller and " - Controller" or "")]
        -- A scroll list is flat: say so when this submenu has submenus of its own.
        if not action.spread and Menu_Live.HasSubmenus(action.menu) then
            submenuText = submenuText .. " " .. L["Config - Menus - Submenu - Flatten"]
        end
        Group(submenuText)
    end
    AddVisibilityGroup(action)
    -- A class or character menu says whose it is, last, in orange like the other notes.
    local owner = action.kind == Menu_Kinds.Kind.Submenu and Menu_Data.GetOwnerLabel(action.menu)
    if owner then GameTooltip:AddLine(owner, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true) end
    GameTooltip:Show()
end

--- The action in the center (the quick action), or nil.
---@return Action?
function PreviewMixin:GetQuickStoredAction()
    return self.menu and Menu_Data.GetQuickAction(self.menu) or nil
end

--- Tooltip for the center: the current quick action and how to change it from the wheel.
function PreviewMixin:ShowCenterTooltip()
    local menu = self.menu
    if not menu then return end
    local owner = self:PlaceLabelAnchor(Private.BELOW, 0)
    self.tooltipOwner = owner
    Private.SetTooltipOutward(owner, Private.BELOW)

    local action = Menu_Data.GetQuickAction(menu)
    -- An empty center closes the menu, like a Close action, so it's named the same.
    local title = Menu_Actions.GetLabel(action or { kind = Menu_Kinds.Kind.Close })
    GameTooltip:SetText(format(L["Config - Menus - Tooltip - QuickTitle"], title), 1, 1, 1)

    if action then
        GameTooltip:AddLine(L["Config - Menus - Tooltip - TapOnly"], nil, nil, nil, true)
    end
    GameTooltip:AddLine(" ")
    local control
    if action and action.kind ~= Menu_Kinds.Kind.LastUsed and action.kind ~= Menu_Kinds.Kind.First then
        -- A double-click only cycles empty, Last Used and First Action. This one goes with the X.
        control = self.readOnly and L["Config - Menus - Preview - Control - QuickSetReadOnly"] or L["Config - Menus - Preview - Control - QuickSet"]
    else
        control = self.readOnly and L["Config - Menus - Preview - Control - QuickReadOnly"] or L["Config - Menus - Preview - Control - Quick"]
    end
    if not self.readOnly then
        -- An empty center drags out as a Close action.
        control = control .. " " .. L[action and "Config - Menus - Preview - Control - QuickToWheel" or "Config - Menus - Preview - Control - CloseToWheel"]
    end
    if action then
        control = control .. " " .. L["Config - Menus - Preview - Control - QuickClear"]
    end
    GameTooltip:AddLine(L["Config - Menus - Tooltip - Control"] .. " " .. control, nil, nil, nil, true)

    -- Same group as an action's tooltip, for the quick action's action.
    AddVisibilityGroup(action)
    GameTooltip:Show()
end

--- Clears every hover and drag display (the mouse left the wheel).
function PreviewMixin:ClearInteraction()
    self.QuickRemove:Hide()
    self:SetSelected(nil)
    self:SetTooltipIndex(nil)
    self:HideTarget()
    self:SetGapTarget(nil)
    self.wheel:SetPointerAngle(nil)
    self.wheel:SetCenterHighlight(false)
end
