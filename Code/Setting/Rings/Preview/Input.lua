--[[
    Rings_Preview (see Preview.lua): the preview's input. Where the cursor is (an icon, a wedge by
    angle, a drop target), hover, presses and double-clicks, reordering by drag, and drops from the
    game. Preview.lua sets the wheel's frame scripts (Private.OnUpdate, OnMouseDown, OnMouseUp).
]]

local env = select(2, ...)
local L = env.L
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Layout = env.AX_Modules:Await("@\\Ring\\Layout")
local Ring_Search = env.AX_Modules:Await("@\\Ring\\Search")
local Private = env.AX_Modules:Import("@\\Setting\\Rings\\Preview\\Private")
local Perf = env.AX_Modules:Import("@\\Perf")
local Ring_Kinds = env.AX_Modules:Await("@\\Ring\\Kinds")

local GetCursorPosition, GetCursorInfo, IsMouseButtonDown = GetCursorPosition, GetCursorInfo, IsMouseButtonDown
local atan2, deg, floor, abs = math.atan2, math.deg, math.floor, math.abs

---@class RingPreview
local PreviewMixin = Private.PreviewMixin

local HOVER_PADDING = 14 -- px around an icon that still count as being on it (covers its X)
local DRAG_THRESHOLD = 6 -- px the mouse must move before a press on an icon becomes a drag
local DOUBLE_CLICK_TIME = 0.35 -- seconds between presses for a double-click
local DRAG_SOURCE_ALPHA = 0.35
-- The share of an action's angle, either side of its center, that counts as over it. The rest of
-- the angle, near the dividers, counts as between.
local OVER_ZONE = 0.3

-- What an empty center drags out as (its drag icon). It's made on first use, because the kind
-- names (Ring_Kinds) load after the settings.
local closeSlice

---@return Slice
local function GetCloseSlice()
    closeSlice = closeSlice or { kind = Ring_Kinds.Kind.Close }
    return closeSlice
end



-- Geometry

--- Whether (`dx`, `dy`) from the wheel center is inside the dead zone (the center).
---@param dx number
---@param dy number
---@return boolean
local function IsInDeadzone(dx, dy)
    local deadzone = Ring_Data.GetDeadzone()
    return dx * dx + dy * dy <= deadzone * deadzone
end

--- The cursor relative to the wheel center, in the wheel's own (unscaled) units, so the dead zone
--- matches the real menu at 100% size.
---@return number dx
---@return number dy
function PreviewMixin:GetCursorDelta()
    local wheel = self.wheel
    local scale = wheel:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local centerX, centerY = wheel:GetCenter()
    return x / scale - centerX, y / scale - centerY
end

--- The wedge whose icon is under the cursor (with padding), if any.
---@return integer?
function PreviewMixin:GetIconUnderCursor()
    local wheel = self.wheel
    for index = 1, wheel.sliceCount do
        local button = wheel.Wedges[index].Button
        if button:IsMouseOver(HOVER_PADDING, -HOVER_PADDING, -HOVER_PADDING, HOVER_PADDING) then
            return index
        end
    end
end

--- The wedge under the cursor by angle (nil in the dead zone or on an empty wheel).
---@param dx number
---@param dy number
---@return integer?
function PreviewMixin:GetSliceByAngle(dx, dy)
    return Ring_Layout.GetSliceIndex(dx, dy, self.wheel.sliceCount, Ring_Data.GetDeadzone())
end

--- Where a drag or drop would land. Each wedge's angle is split into a middle part (over that
--- action) and its two edges (between it and its neighbor).
---@param dx number
---@param dy number
---@return table target `mode` is a Private.Target value.
---     { mode = Center }                                the dead zone
---     { mode = Add }                                   an empty wheel, outside the dead zone
---     { mode = Over, index = k }                       over action k
---     { mode = Between, index = k, angle = radians }   insert so the new action becomes #k, with
---                                                      the angle of the divider it goes on
function PreviewMixin:GetDropTarget(dx, dy)
    local count = self.wheel.sliceCount
    if IsInDeadzone(dx, dy) then return { mode = Private.Target.Center } end
    if count == 0 then return { mode = Private.Target.Add } end

    local step = 360 / count
    local position = ((90 - deg(atan2(dy, dx))) % 360) / step -- wedge i is centered at i - 1
    local nearest = floor(position + 0.5)
    if abs(position - nearest) <= OVER_ZONE then
        return { mode = Private.Target.Over, index = nearest % count + 1 }
    end

    -- Between wedge `after` and the next one clockwise. The divider is on after's clockwise edge.
    local after = floor(position) % count + 1
    return { mode = Private.Target.Between, index = after + 1, angle = Ring_Layout.GetBoundaryAngle(after, count) }
end





-- Drop from the game

--- Adds what the cursor holds, where it was dropped.
function PreviewMixin:HandleDrop()
    if not self.ring then return end
    if self.locked then
        env.Print(L["Config - Rings - OtherClass - Locked"])
        return
    end
    if self.readOnly then
        env.Print(L["Config - Rings - Auto - Locked"])
        return
    end
    local slice, err = Ring_Search.SliceFromCursor()
    if not slice then
        if err then env.Print(err) end
        return
    end

    local dx, dy = self:GetCursorDelta()
    local target = self:GetDropTarget(dx, dy)
    local ok
    if target.mode == Private.Target.Over then
        ok = self.callbacks.onReplace and self.callbacks.onReplace(target.index, slice)
    elseif target.mode == Private.Target.Center then
        ok = self.callbacks.onSetQuick and self.callbacks.onSetQuick(slice)
    else
        -- Between inserts at that position, and Add (an empty menu) adds it.
        local index = target.mode == Private.Target.Between and target.index or nil
        ok = self.callbacks.onDrop and self.callbacks.onDrop(slice, index)
    end
    if ok then ClearCursor() end
    self:HideTarget()
end



-- Reorder

--- A mouse press on a wedge or on the center's quick action. It becomes a drag once the cursor
--- moves past DRAG_THRESHOLD (UpdateDrag).
---@param index integer|string a wedge index, or Private.QUICK
function PreviewMixin:BeginDrag(index)
    local x, y = GetCursorPosition()
    self.drag = { from = index, startX = x, startY = y, active = false }
end

--- What the center shows: its action, or the cancel X when it's empty.
---@return Frame|Texture
function PreviewMixin:GetCenterIcon()
    return Ring_Data.GetQuickActionSlice(self.ring) and self.wheel.Quick or self.wheel.CancelIcon
end

--- Ends the drag in progress.
---@param apply boolean carry out the move, swap or quick action change (false just cancels)
function PreviewMixin:EndDrag(apply)
    local drag = self.drag
    if not drag then return end
    self.drag = nil

    local source = drag.from == Private.QUICK and self:GetCenterIcon() or self.wheel.Wedges[drag.from]
    if source then (source.Button or source):SetAlpha(1) end
    self.DragIcon:Hide()
    self:HideTarget()

    local target = drag.target
    if not (apply and drag.active and target) then return end

    if drag.from == Private.QUICK then
        -- The center's action onto the wheel (a Close action when it's empty).
        local replace = target.mode == Private.Target.Over
        -- A submenu or action bar can't swap into the center (the drag label says so).
        local over = replace and self.ring and self:GetSlice(target.index)
        if over and not Ring_Data.CanBeQuickAction(over) then return end
        if replace or target.mode == Private.Target.Between or target.mode == Private.Target.Add then
            if self.callbacks.onQuickToWheel then self.callbacks.onQuickToWheel(target.index, replace) end
        end
        return
    end

    if target.mode == Private.Target.Center then
        local slice = self.ring and self:GetSlice(drag.from)
        if slice and Ring_Data.CanBeQuickAction(slice) and self.callbacks.onQuickFromSlice then self.callbacks.onQuickFromSlice(drag.from) end
    elseif target.mode == Private.Target.Over and target.index ~= drag.from then
        if self.callbacks.onSwap then self.callbacks.onSwap(drag.from, target.index) end
    elseif target.mode == Private.Target.Between then
        -- target.index is the position before removal. After taking the action out, later
        -- positions shift down by one.
        local to = target.index > drag.from and target.index - 1 or target.index
        if to > self.wheel.sliceCount then to = self.wheel.sliceCount end
        if to ~= drag.from and self.callbacks.onMove then self.callbacks.onMove(drag.from, to) end
    end
end

--- Moves the drag in progress with the cursor, and shows where it would land.
function PreviewMixin:UpdateDrag()
    local drag = self.drag --[[@as table]] -- only called while dragging
    if not IsMouseButtonDown("LeftButton") then
        -- The button was released without OnMouseUp reaching the preview (focus lost), so the
        -- drag is dropped.
        self:EndDrag(false)
        return
    end

    local x, y = GetCursorPosition()
    if not drag.active then
        local uiScale = UIParent:GetEffectiveScale()
        local moved = ((x - drag.startX) ^ 2 + (y - drag.startY) ^ 2) ^ 0.5 / uiScale
        if moved < DRAG_THRESHOLD then return end

        drag.active = true
        self:SetTooltipIndex(nil)
        if drag.from == Private.QUICK then
            Ring_Layout.SetSliceIcon(self.DragIcon, Ring_Data.GetQuickActionSlice(self.ring) or GetCloseSlice())
            self:GetCenterIcon():SetAlpha(DRAG_SOURCE_ALPHA)
        else
            local slice = self.ring and self:GetShownSlice(drag.from)
            Ring_Layout.SetSliceIcon(self.DragIcon, slice)
            self.wheel.Wedges[drag.from].Button:SetAlpha(DRAG_SOURCE_ALPHA)
        end
        self.DragIcon:Show()
    end

    local uiScale = UIParent:GetEffectiveScale()
    self.DragIcon:ClearAllPoints()
    self.DragIcon:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / uiScale, y / uiScale)

    local wheel = self.wheel
    if wheel:IsMouseOver() then
        local dx, dy = self:GetCursorDelta()
        drag.target = self:GetDropTarget(dx, dy)
        self:ShowTarget(drag.target, drag.from, dx, dy)
    else
        drag.target = nil
        self:SetSelected(nil)
        self:HideTarget()
        wheel:SetPointerAngle(nil)
        wheel:SetCenterHighlight(false)
    end
end



-- Frame scripts

local Update -- the per-frame work (below), which Private.OnUpdate times for the performance log

--- The wheel's OnUpdate.
---@param wheel RingWheel
function Private.OnUpdate(wheel)
    if not Perf.enabled then return Update(wheel) end
    local start = debugprofilestop()
    Update(wheel)
    Perf.CountPreviewFrame(debugprofilestop() - start)
end

Update = function(wheel)
    local preview = wheel.preview --[[@as RingPreview]]
    if preview.drag then
        preview:SetGapTarget(nil)
        preview.QuickRemove:Hide()
        preview:UpdateDrag()
        return
    end

    local holding = GetCursorInfo() ~= nil and not preview.readOnly
    if holding then preview.QuickRemove:Hide() end
    if not wheel:IsMouseOver() or not preview.ring then
        preview:ClearInteraction()
        return
    end

    local dx, dy = preview:GetCursorDelta()
    local inCenter = IsInDeadzone(dx, dy)
    if wheel.sliceCount == 0 and not holding and not inCenter then
        preview:ClearInteraction()
        return
    end

    if holding then
        -- It shows where a drop would land: replace, insert between, or add at the end.
        preview:SetTooltipIndex(nil)
        preview:SetGapTarget(nil)
        preview:ShowTarget(preview:GetDropTarget(dx, dy), nil, dx, dy)
        return
    end
    preview:HideTarget()

    local iconIndex = preview:GetIconUnderCursor()

    -- In a gap between two actions (and not on an icon), it offers a "+" to add an action right
    -- there, instead of highlighting an action.
    local target = not iconIndex and preview:GetDropTarget(dx, dy)
    local gapTarget = target and target.mode == Private.Target.Between and target or nil
    preview:SetGapTarget(gapTarget)

    local index = iconIndex or (not gapTarget and preview:GetSliceByAngle(dx, dy)) or nil
    preview:SetSelected(index)
    -- The center (quick action) has its own tooltip. A single-action menu's center is the action.
    local centerTip = inCenter and not iconIndex and not wheel.isSingleCentered
    preview:SetTooltipIndex(iconIndex or (centerTip and Private.CENTER) or nil)
    -- The X on the center while hovering it, when there's a quick action (it's cleared with it).
    preview.QuickRemove:SetShown(centerTip and not preview.locked and preview:GetQuickStoredSlice() ~= nil or false)
    wheel:SetPointerAngle(index and atan2(dy, dx) or nil)
    wheel:SetCenterHighlight(index == nil and not gapTarget)
end

--- The wheel's OnMouseDown.
---@param wheel RingWheel
---@param button string
function Private.OnMouseDown(wheel, button)
    local preview = wheel.preview --[[@as RingPreview]]
    if button ~= "LeftButton" or GetCursorInfo() or preview.locked then return end

    local index = preview:GetIconUnderCursor()
    local now = GetTime()

    -- On the center (quick action), a double-click cycles the quick action, and its action can be
    -- dragged from there onto the wheel.
    if not index and not wheel.isSingleCentered then
        local dx, dy = preview:GetCursorDelta()
        if not IsInDeadzone(dx, dy) then return end
        if preview.lastPressIndex == Private.CENTER and now - preview.lastPressTime <= DOUBLE_CLICK_TIME then
            preview.lastPressIndex = nil
            if preview.callbacks.onToggleQuick then preview.callbacks.onToggleQuick() end
            return
        end
        preview.lastPressIndex, preview.lastPressTime = Private.CENTER, now
        -- Its action, or a Close action when it's empty (an empty center cancels, like Close).
        if preview.ring and not preview.readOnly then preview:BeginDrag(Private.QUICK) end
        return
    end
    if not index then return end

    -- A double-click on a submenu switches it between scrolling and spreading its actions.
    local slice = preview.ring and preview:GetSlice(index)
    if slice and slice.kind == Ring_Kinds.Kind.Ring and preview.lastPressIndex == index
        and now - preview.lastPressTime <= DOUBLE_CLICK_TIME then
        preview.lastPressIndex = nil
        if preview.callbacks.onToggleExpand then preview.callbacks.onToggleExpand(index) end
        return
    end
    preview.lastPressIndex, preview.lastPressTime = index, now
    preview:BeginDrag(index)
end

--- The wheel's OnMouseUp.
---@param wheel RingWheel
---@param button string
function Private.OnMouseUp(wheel, button)
    local preview = wheel.preview --[[@as RingPreview]]
    if button ~= "LeftButton" then return end

    if GetCursorInfo() then
        preview:HandleDrop()
    elseif preview.drag then
        preview:EndDrag(wheel:IsMouseOver())
    end
end
