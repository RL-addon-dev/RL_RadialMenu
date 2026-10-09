--[[
    Settings preview: input. Where the cursor is (icon, slice by angle, drop target), hover,
    presses and double-clicks, reordering by drag, and drops from the game. The wheel's frame
    scripts (Private.OnUpdate / OnMouseDown / OnMouseUp) are set in Preview.lua.
]]

local env = select(2, ...)
local L = env.L
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Layout = env.AX_Modules:Await("@\\Ring\\Layout")
local Ring_Search = env.AX_Modules:Await("@\\Ring\\Search")
local Private = env.AX_Modules:Import("@\\Setting\\Rings\\Preview\\Private")

local GetCursorPosition, GetCursorInfo, IsMouseButtonDown = GetCursorPosition, GetCursorInfo, IsMouseButtonDown
local atan2, deg, floor, abs, cos, sin, pi = math.atan2, math.deg, math.floor, math.abs, math.cos, math.sin, math.pi
local PreviewMixin = Private.PreviewMixin

local HOVER_PADDING = 14 -- px around an icon that still counts as being on it (covers its X)
local DRAG_THRESHOLD = 6 -- px the mouse must move before a press on an icon becomes a drag
local DOUBLE_CLICK_TIME = 0.35 -- s between presses on a nested ring to switch scroll / expand
local DRAG_SOURCE_ALPHA = 0.35
-- Share of a slice's angle, either side of its center, that counts as "over" it (the rest of
-- the angle, near the dividers, counts as "between").
local OVER_ZONE = 0.3



-- Geometry

--- Cursor relative to the wheel center, in the wheel's own (unscaled) units, so the dead zone
--- matches the real ring at 100% size.
function PreviewMixin:GetCursorDelta()
    local wheel = self.wheel
    local scale = wheel:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local centerX, centerY = wheel:GetCenter()
    return x / scale - centerX, y / scale - centerY
end

--- Icon under the cursor (with padding), if any.
function PreviewMixin:GetIconUnderCursor()
    local wheel = self.wheel
    for index = 1, wheel.sliceCount do
        local button = wheel.Wedges[index].Button
        if button:IsMouseOver(HOVER_PADDING, -HOVER_PADDING, -HOVER_PADDING, HOVER_PADDING) then
            return index
        end
    end
end

--- Slice position under the cursor by angle (nil in the dead zone or on an empty wheel).
function PreviewMixin:GetSliceByAngle(dx, dy)
    return Ring_Layout.GetSliceIndex(dx, dy, self.wheel.sliceCount, Ring_Data.GetDeadzone())
end

--- Where a drag / drop would land. Each slice's angle is split into a middle part ("over" that
--- slice) and its two edges ("between" it and its neighbor).
--- @return table target
---     { mode = "center" }                                   dead zone or empty wheel
---     { mode = "over", index = k }                          over slice k
---     { mode = "between", index = k, angle = radians }      insert so the new slice becomes #k;
---                                                           angle = the divider it goes on
function PreviewMixin:GetDropTarget(dx, dy)
    local count = self.wheel.sliceCount
    local deadzone = Ring_Data.GetDeadzone()
    if dx * dx + dy * dy <= deadzone * deadzone then return { mode = "center" } end
    if count == 0 then return { mode = "add" } end

    local step = 360 / count
    local position = ((90 - deg(atan2(dy, dx))) % 360) / step -- slice i is centered at i - 1
    local nearest = floor(position + 0.5)
    if abs(position - nearest) <= OVER_ZONE then
        return { mode = "over", index = nearest % count + 1 }
    end

    -- Between slice `after` and the next one clockwise; the divider sits on after's clockwise edge.
    local after = floor(position) % count + 1
    return { mode = "between", index = after + 1, angle = Ring_Layout.GetSliceAngle(after, count) - pi / count }
end





-- Drop from the game

function PreviewMixin:HandleDrop()
    if not self.ring then return end
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
    if target.mode == "over" then
        ok = self.callbacks.onReplace and self.callbacks.onReplace(target.index, slice)
    elseif target.mode == "center" then
        ok = self.callbacks.onSetQuick and self.callbacks.onSetQuick(slice)
    else
        -- "between" inserts at that position; "add" (empty ring) adds it.
        ok = self.callbacks.onDrop and self.callbacks.onDrop(slice, target.mode == "between" and target.index or nil)
    end
    if ok then ClearCursor() end
    self:HideTarget()
end



-- Reorder

--- Mouse down on a slice (`index`) or the tap-only quick action ("quick"); it becomes a drag once
--- the cursor moves past DRAG_THRESHOLD (UpdateDrag).
function PreviewMixin:BeginDrag(index)
    local x, y = GetCursorPosition()
    self.drag = { from = index, startX = x, startY = y, active = false }
end

--- @param apply boolean carry out the move / swap / quick action change (false: just cancel)
function PreviewMixin:EndDrag(apply)
    local drag = self.drag
    if not drag then return end
    self.drag = nil

    local source = drag.from == "quick" and self.wheel.Quick or self.wheel.Wedges[drag.from]
    if source then (source.Button or source):SetAlpha(1) end
    self.DragIcon:Hide()
    self:HideTarget()

    local target = drag.target
    if not (apply and drag.active and target) then return end

    if drag.from == "quick" then
        -- The tap-only quick action onto the wheel.
        if target.mode == "over" or target.mode == "between" or target.mode == "add" then
            local replace = target.mode == "over"
            if self.callbacks.onQuickToWheel then self.callbacks.onQuickToWheel(target.index, replace) end
        end
        return
    end

    if target.mode == "center" then
        local slice = self.ring and self:GetSlice(drag.from)
        if slice and slice.kind ~= "ring" and self.callbacks.onQuickFromSlice then self.callbacks.onQuickFromSlice(drag.from) end
    elseif target.mode == "over" and target.index ~= drag.from then
        if self.callbacks.onSwap then self.callbacks.onSwap(drag.from, target.index) end
    elseif target.mode == "between" then
        -- target.index is the position before removal; after taking the slice out, later
        -- positions shift down by one.
        local to = target.index > drag.from and target.index - 1 or target.index
        if to > self.wheel.sliceCount then to = self.wheel.sliceCount end
        if to ~= drag.from and self.callbacks.onMove then self.callbacks.onMove(drag.from, to) end
    end
end

function PreviewMixin:UpdateDrag()
    local drag = self.drag
    if not IsMouseButtonDown("LeftButton") then
        -- Button released without OnMouseUp reaching us (e.g. focus lost): drop the drag.
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
        if drag.from == "quick" then
            Ring_Layout.SetSliceIcon(self.DragIcon, self.ring.quickSlice)
            self.wheel.Quick:SetAlpha(DRAG_SOURCE_ALPHA)
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

function Private.OnUpdate(wheel)
    local preview = wheel.preview
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
    local deadzone = Ring_Data.GetDeadzone()
    local inCenter = dx * dx + dy * dy <= deadzone * deadzone
    if wheel.sliceCount == 0 and not holding and not inCenter then
        preview:ClearInteraction()
        return
    end

    if holding then
        -- Show where a drop would land: replace, insert between, or add at the end.
        preview:SetTooltipIndex(nil)
        preview:SetGapTarget(nil)
        preview:ShowTarget(preview:GetDropTarget(dx, dy), nil, dx, dy)
        return
    end
    preview:HideTarget()

    local iconIndex = preview:GetIconUnderCursor()

    -- In a gap between two slices (and not on an icon), offer a "+" to add a slice right there,
    -- instead of highlighting a slice.
    local target = not iconIndex and preview:GetDropTarget(dx, dy)
    local gapTarget = target and target.mode == "between" and target or nil
    preview:SetGapTarget(gapTarget)

    local index = iconIndex or (not gapTarget and preview:GetSliceByAngle(dx, dy)) or nil
    preview:SetSelected(index)
    -- The center (quick action) has its own tooltip; a single-slice ring's center is the slice.
    local centerTip = inCenter and not iconIndex and not wheel.isSingleCentered
    preview:SetTooltipIndex(iconIndex or (centerTip and "center") or nil)
    -- X on the center while hovering it, when the quick action is a slice (Last Used Slice and
    -- None are switched with a double-click instead).
    preview.QuickRemove:SetShown(centerTip and preview:GetQuickStoredSlice() ~= nil or false)
    wheel:SetPointerAngle(index and atan2(dy, dx) or nil)
    wheel:SetCenterHighlight(index == nil and not gapTarget)
end

function Private.OnMouseDown(wheel, button)
    local preview = wheel.preview
    if button ~= "LeftButton" or GetCursorInfo() then return end

    local index = preview:GetIconUnderCursor()
    local now = GetTime()

    -- The center (quick action): double-click switches None / Last Used Slice; a tap-only quick
    -- action can be dragged from there onto the wheel.
    if not index and not wheel.isSingleCentered then
        local dx, dy = preview:GetCursorDelta()
        local deadzone = Ring_Data.GetDeadzone()
        if dx * dx + dy * dy > deadzone * deadzone then return end
        if preview.lastPressIndex == "center" and now - preview.lastPressTime <= DOUBLE_CLICK_TIME then
            preview.lastPressIndex = nil
            if preview.callbacks.onToggleQuick then preview.callbacks.onToggleQuick() end
            return
        end
        preview.lastPressIndex, preview.lastPressTime = "center", now
        local ring = preview.ring
        if ring and ring.quickAction == Ring_Data.QuickAction.Custom and ring.quickSlice and not preview.readOnly then
            preview:BeginDrag("quick")
        end
        return
    end
    if not index then return end

    -- Double-click a nested ring: switch between scrolling and spreading its slices.
    local slice = preview.ring and preview:GetSlice(index)
    if slice and slice.kind == "ring" and preview.lastPressIndex == index
        and now - preview.lastPressTime <= DOUBLE_CLICK_TIME then
        preview.lastPressIndex = nil
        if preview.callbacks.onToggleExpand then preview.callbacks.onToggleExpand(index) end
        return
    end
    preview.lastPressIndex, preview.lastPressTime = index, now
    preview:BeginDrag(index)
end

function Private.OnMouseUp(wheel, button)
    local preview = wheel.preview
    if button ~= "LeftButton" then return end

    if GetCursorInfo() then
        preview:HandleDrop()
    elseif preview.drag then
        preview:EndDrag(wheel:IsMouseOver())
    end
end
