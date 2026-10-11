--[[
    Live wheel preview for the Menus tab: the same Ring_Layout wheel as the in-game ring.

    Behaves like the real ring while the mouse is over it, measured from the wheel's center:
    the pointer follows the cursor angle, the slice is picked by angle outside the dead zone,
    and the center highlights inside it. While the cursor is on an icon (or its X), that slice
    stays selected so the X is always reachable. The selected slice shows a small X; clicking it
    removes the slice. Hovering an icon also shows its name in a tooltip.

    Drag & drop:
      Each slice's angle has a middle part ("over" the slice) and edges ("between" slices).
      A gold wedge marks "over", a gold divider line marks "between", and a GameTooltip pointing
      out of the wheel from the target says what releasing will do.

      from the game   a spell / item / toy / macro / mount on the cursor: over a slice replaces
                      it, between two slices inserts it there (the gap before the first slice adds
                      at the end), the center makes it a tap-only quick action. On an empty ring,
                      anywhere outside the center adds it. Works with drag-release or
                      pick-up-then-click.
      reorder         press on a slice icon and drag (the icon follows the cursor): over another
                      slice swaps the two, between two slices moves it there, the center copies it
                      there (it stays on the wheel; it replaces what the center had). Releasing
                      off the wheel cancels.
      quick action    the center is a slot: press on it and drag its action onto the wheel: over a
                      slice swaps the two (not with a submenu or action bar, which can't be in
                      the center), between two slices inserts it there. An empty center drags out as a Close
                      action (it cancels, like Close). Nested rings and action bars can't be in
                      the center (the drag label says so).

    Double-click: the center switches between empty (Close Menu) and a Last Used action (another
    quick action is only cleared with the center's X); a nested ring slice switches between scroll
    and spread.

    Center icon, like the real ring before the mouse moves: the quick action's icon (a Last Used
    action shows the question mark here, the last action's icon in game); empty shows cancel.
    Badges and the X on the center follow the quick action.
    Read-only (built-in rings, which fill themselves): slices can be rearranged by dragging and
    removed with the X (remembered, see Ring_Data BuiltIn.lua), but there's no "+" and nothing
    can be dropped in from the game.

    A ring with one slice shows that slice in the center instead (hover, X, tooltip and drag work
    on it there, since they follow the icon).

    Another class's or character's submenu (inside an account menu) is always left out: it
    doesn't exist on this character.

    Hide Hidden Actions (the eye in the top corner, PreviewHideHidden): slices hidden in game right
    now are left out too. The wheel's indices are then positions among the shown slices
    (self.shown[index] = stored index); callbacks translate them back (StoredCallbacks), so edits
    still work. A slice placed between two shown slices lands right before the second one, after
    any hidden slices in between.

    Files (one module, Rings_Preview; shared state on the preview object, helpers in
    "@\\Setting\\Rings\\Preview\\Private"):
        Preview.lua     this file: building the preview, SetRing / SetReadOnly
        Display.lua     what it shows: selection, drop target, drag labels, tooltips, the gap "+"
        Input.lua       what it does: hit testing, hover, press, drag, drop, double-click
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Layout = env.AX_Modules:Await("@\\Ring\\Layout")
local Ring_Live = env.AX_Modules:Await("@\\Ring\\Live")
local UIFont = env.AX_Modules:Import("ax_modules\\ui-font")
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Text = UIKit.UI.Frames[5]
local UICCommon = env.AX_Modules:Import("ax_modules\\uic-common")
local GenericEnum = env.AX_Modules:Import("ax_modules\\generic-enum")
local Rings_Preview = env.AX_Modules:New("@\\Setting\\Rings\\Preview")
local Private = env.AX_Modules:New("@\\Setting\\Rings\\Preview\\Private")

local pi = math.pi

local PREVIEW_SCALE = 1 -- same size as the in-game ring at the default Ring Size
local REMOVE_SIZE = 20
local REMOVE_OFFSET = 12 -- X center sits this far in from the corner, minus half its size (2px inside the icon)
local QUICK_REMOVE_SCALE = 0.8 -- the center icon is smaller than a slice icon
local DRAG_ICON_SIZE = 36
local INSERT_LINE_COLOR = { 1, 0.82, 0, 0.95 }
-- "+" on the gap between two slices (hovered), to add a slice at that spot.
local GAP_BUTTON_SIZE = 26
local GAP_BUTTON_RADIUS = 128
Private.GAP_BUTTON_SIZE, Private.GAP_BUTTON_RADIUS = GAP_BUTTON_SIZE, GAP_BUTTON_RADIUS

-- Fits what you interact with (icons and the gap "+", out to GAP_BUTTON_RADIUS), not the whole
-- wheel art: the faded background and highlight wedges may reach a little past it.
local PREVIEW_MARGIN = 6
Rings_Preview.HEIGHT = math.ceil(2 * (GAP_BUTTON_RADIUS + GAP_BUTTON_SIZE / 2) * PREVIEW_SCALE) + 2 * PREVIEW_MARGIN
local EYE_SIZE = 24


--- Methods of the preview object; Display.lua and Input.lua add theirs.
local PreviewMixin = {}
Private.PreviewMixin = PreviewMixin

--- The stored slice at wheel position `index` (Hide Hidden Actions leaves some out), and what it
--- shows (a scroll submenu shows its current child).
function PreviewMixin:GetSlice(index)
    local stored = index and self.shown[index]
    return stored and self.ring.slices[stored]
end

function PreviewMixin:GetShownSlice(index)
    local stored = index and self.shown[index]
    return stored and Ring_Live.GetStoredShownSlice(self.ring, stored)
end

--- The callbacks with wheel positions turned back into stored indices (the others are passed
--- through). A gap position (insert so the new slice becomes #index) goes right before that shown
--- slice, or at the end past the last.
local function StoredCallbacks(preview, callbacks)
    local function Stored(index) return index and preview.shown[index] end
    local function Gap(index) return index and (preview.shown[index] or #preview.ring.slices + 1) end
    local function Call(name, ...)
        if callbacks[name] then return callbacks[name](...) end
    end
    return setmetatable({
        onAdd            = function(index) return Call("onAdd", Gap(index)) end,
        onRemove         = function(index) return Call("onRemove", Stored(index)) end,
        onToggleExpand   = function(index) return Call("onToggleExpand", Stored(index)) end,
        onQuickFromSlice = function(index) return Call("onQuickFromSlice", Stored(index)) end,
        onQuickToWheel   = function(index, replace) return Call("onQuickToWheel", replace and Stored(index) or Gap(index), replace) end,
        onSwap           = function(a, b) return Call("onSwap", Stored(a), Stored(b)) end,
        onDrop           = function(slice, index) return Call("onDrop", slice, Gap(index)) end,
        onReplace        = function(index, slice) return Call("onReplace", Stored(index), slice) end,
        -- `to` is its position once taken out: the gap it was dropped into, before removal.
        onMove           = function(from, to)
            local fromStored, gap = Stored(from), Gap(to >= from and to + 1 or to)
            return Call("onMove", fromStored, gap > fromStored and gap - 1 or gap)
        end,
    }, { __index = callbacks })
end

local function IsHidingHidden()
    return Config.DBGlobal and Config.DBGlobal:GetVariable("PreviewHideHidden") and true or false
end

--- X on an icon's top-right corner. `onClick` defaults to removing the wedge's slice.
local function CreateRemoveButton(preview, wedge, onClick)
    local button = CreateFrame("Button", nil, wedge.Button)
    button:SetSize(REMOVE_SIZE, REMOVE_SIZE)
    button:SetPoint("CENTER", wedge.Button, "TOPRIGHT", -REMOVE_OFFSET + REMOVE_SIZE / 2, -REMOVE_OFFSET + REMOVE_SIZE / 2)
    button:SetFrameLevel(preview.wheel:GetFrameLevel() + 10)

    button.Texture = button:CreateTexture(nil, "OVERLAY")
    button.Texture:SetAllPoints()
    button.Texture:SetAtlas(Ring_Layout.ATLAS_CANCEL_ICON)
    button:SetAlpha(0.8)

    button:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    button:SetScript("OnLeave", function(self) self:SetAlpha(0.8) end)
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if onClick then
            onClick()
        elseif preview.callbacks.onRemove then
            preview.callbacks.onRemove(wedge.index)
        end
    end)

    button:Hide()
    wedge.RemoveButton = button
    return button
end



--- Read-only previews (automatic rings) can't be edited from the wheel.
--- @param builtInKey string|nil the built-in ring's key, for its "nothing here yet" text
function PreviewMixin:SetReadOnly(readOnly, builtInKey)
    self.readOnly = readOnly or false
    local emptyText = self.readOnly and L["Config - Rings - Auto - Empty - " .. tostring(builtInKey)]
    self.emptyText = emptyText or L["Config - Rings - Preview - Empty"] -- shown by SetRing
end

--- Redraws the wheel for `ring` (nil clears it).
function PreviewMixin:SetRing(ring)
    self:EndDrag(false)
    self.ring = ring
    self.selectedIndex = nil
    self.tooltipIndex = nil
    if self.tooltipOwner and GameTooltip:GetOwner() == self.tooltipOwner then GameTooltip:Hide() end
    self.tooltipOwner = nil

    local wheel = self.wheel
    -- The slices on the wheel: all of them, or (Hide Hidden Actions) the ones shown in game now.
    -- Another class's or character's submenu is never on it (it doesn't exist here).
    local hideHidden = IsHidingHidden()
    self.shown = {}
    local slices, hiddenCount = {}, 0
    for index, slice in ipairs(ring and ring.slices or {}) do
        if Ring_Data.IsElsewhere(slice) then
            -- left out
        elseif hideHidden and not Ring_Actions.IsSliceAvailable(slice) then
            hiddenCount = hiddenCount + 1
        else
            self.shown[#self.shown + 1] = index
            slices[#slices + 1] = slice
        end
    end
    self:UpdateEyeButton(hiddenCount)
    -- Scroll slices show the child's current slice, like the in-game ring.
    local displaySlices = {}
    for index = 1, #slices do
        displaySlices[index] = self:GetShownSlice(index)
    end
    local hasTapOnly = ring ~= nil and Ring_Data.GetQuickActionSlice(ring) ~= nil
    wheel:SetSlices(displaySlices, nil, hasTapOnly)
    wheel:SetScrollBadges(slices)
    wheel:SetConditionBadges(slices)
    for i = 1, #wheel.Wedges do
        local wedge = wheel.Wedges[i]
        wedge.Button:SetAlpha(1)
        if wedge.RemoveButton then wedge.RemoveButton:Hide() end
    end
    wheel:SetPointerAngle(nil)

    local quickIcon, quickSlice
    if #slices == 0 then
        quickIcon = nil -- nothing to fire yet: show cancel
    elseif ring then
        quickSlice = Ring_Data.GetQuickActionSlice(ring)
        -- Hide Hidden Actions: a hidden quick action leaves the center to cancel, like in game.
        if hideHidden and quickSlice and not Ring_Actions.IsSliceAvailable(quickSlice) then quickSlice = nil end
        quickIcon = quickSlice and Ring_Actions.GetIcon(quickSlice)
    end
    wheel:SetQuickIcon(quickIcon, quickSlice)
    -- A single slice sits in the center and is itself the quick action, unless a tap-only quick
    -- action owns the center (Ring_Layout / Ring_Secure).
    wheel:SetCenter(quickIcon ~= nil or wheel.isSingleCentered, false)
    wheel:SetQuickBadges(self:GetQuickStoredSlice())
    wheel:SetCenterHighlight(false)

    -- Nothing on the wheel: an empty menu, or (Hide Hidden Actions) all of it hidden right now.
    local allHidden = #slices == 0 and hiddenCount > 0
    self.Empty:SetText(allHidden and L["Config - Rings - Preview - AllHidden"] or self.emptyText)
    self.Empty:SetShown(#slices == 0)
    self:SetGapTarget(nil) -- places the "+" on an empty ring, hides it otherwise
end

--- The eye toggle shows the current state: crossed out while hidden actions are left out, with
--- how many are (`hiddenCount`) beside it.
function PreviewMixin:UpdateEyeButton(hiddenCount)
    local hiding = IsHidingHidden()
    local atlas = Ring_Layout.GetEyeAtlas(hiding)
    if atlas then self.EyeButton.Texture:SetAtlas(atlas) end
    self.EyeButton:SetAlpha(hiding and 1 or 0.6)
    local count = hiding and hiddenCount or 0
    self.EyeCount:SetText(count > 0 and format(L["Config - Rings - Preview - HiddenCount"], count) or "")
end

--- @param host Frame frame to center the wheel in (at least Rings_Preview.HEIGHT tall)
--- @param callbacks table
---     onAdd(index)                     the "+" on a gap was clicked (insert so the new slice is #index)
---     onRemove(index)                  a slice's X was clicked
---     onToggleExpand(index)            a nested ring slice was double-clicked (scroll <-> expand)
---     onSetQuick(slice) -> ok          dropped from the game onto the center (tap-only quick action)
---     onQuickFromSlice(index)          a slice was dragged onto the center (quick action = it)
---     onQuickToWheel(index, replace)   the tap-only quick action was dragged onto the wheel
---     onToggleQuick()                  the center was double-clicked (None <-> Last Used Slice)
---     onClearQuick()                   the center's X was clicked (quick action = None)
---     onSwap(a, b)                     a slice was dragged onto another slice
---     onMove(from, to)                 a slice was dragged between two slices (ends up at `to`)
---     onDrop(slice, index) -> ok       dropped from the game between slices (index nil = at the end)
---     onReplace(index, slice) -> ok    dropped from the game onto a slice
function Rings_Preview.Create(host, callbacks)
    local preview = CreateFromMixins(PreviewMixin)
    preview.callbacks = StoredCallbacks(preview, callbacks or {})
    preview.shown = {}

    local wheel = Ring_Layout.CreateWheel(host)
    wheel:SetScale(PREVIEW_SCALE)
    wheel:SetPoint("CENTER", host, "CENTER", 0, 0)
    wheel:EnableMouse(true)
    wheel.preview = preview
    wheel.onWedgeCreated = function(_, wedge) CreateRemoveButton(preview, wedge) end
    wheel:SetScript("OnUpdate", Private.OnUpdate)
    wheel:SetScript("OnMouseDown", Private.OnMouseDown)
    wheel:SetScript("OnMouseUp", Private.OnMouseUp)
    wheel:SetScript("OnReceiveDrag", function() preview:HandleDrop() end)
    wheel:SetScript("OnHide", function()
        preview:EndDrag(false)
        preview:ClearInteraction()
    end)
    preview.wheel = wheel

    -- X on the center: clears the quick action (to None).
    preview.QuickRemove = CreateRemoveButton(preview, { Button = wheel.Quick }, function()
        if preview.callbacks.onClearQuick then preview.callbacks.onClearQuick() end
    end)
    preview.QuickRemove:SetScale(QUICK_REMOVE_SCALE)

    -- Icon that follows the cursor while reordering.
    preview.DragIcon = Ring_Layout.CreateActionIcon(UIParent, DRAG_ICON_SIZE)
    preview.DragIcon:SetFrameStrata("TOOLTIP")
    preview.DragIcon:Hide()

    -- "+" on a hovered gap between two slices: opens Add Slice to insert there. Same red button
    -- art as "+ Add Slice", in its square variant.
    local gap = UICCommon.ButtonRedSquare("RLRM_RingPreview.GapButton", {
        Text("RLRM_RingPreview.GapButton.Text")
            :id("GapText", "RLRM_RingPreview.GapButton")
            :fontObject(UIFont.UIFontObjectNormal14)
            :textColor(GenericEnum.UIColorRGB.NormalText)
            :textAlignment("CENTER", "MIDDLE")
            :size(UIKit.UI.FILL)
    })
        :parent(wheel)
        :size(GAP_BUTTON_SIZE, GAP_BUTTON_SIZE)
    gap.Text = UIKit.GetElementById("GapText", "RLRM_RingPreview.GapButton")
    gap.Text:SetText("+")
    gap:SetFrameLevel(wheel:GetFrameLevel() + 12)
    gap:HookMouseEnter(function(self)
        Private.SetTooltipOutward(self, self.tooltipAngle or -pi / 2)
        GameTooltip:SetText(L["Config - Rings - AddSlice"], 1, 1, 1)
        GameTooltip:Show()
    end)
    gap:HookMouseLeave(function() GameTooltip:Hide() end)
    gap:HookClick(function(self)
        if preview.callbacks.onAdd then preview.callbacks.onAdd(self.insertIndex) end
    end)
    gap:_Render()
    gap:Hide()
    preview.GapButton = gap

    -- Gold line on the divider where a slice would be inserted.
    preview.InsertLine = wheel:CreateLine(nil, "OVERLAY", nil, 5)
    preview.InsertLine:SetThickness(4)
    preview.InsertLine:SetColorTexture(unpack(INSERT_LINE_COLOR))
    preview.InsertLine:Hide()

    -- Invisible anchor for the "Swap" / "Move here" / "Replace" / "Insert" / "Add to end"
    -- tooltip on a divider or the center (slice targets anchor to the slice's icon).
    preview.LabelAnchor = CreateFrame("Frame", nil, wheel)
    preview.LabelAnchor:SetSize(GAP_BUTTON_SIZE, GAP_BUTTON_SIZE)

    preview.Empty = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    preview.Empty:SetPoint("CENTER", wheel, "CENTER", 0, -70)
    preview.Empty:SetWidth(240)
    preview.emptyText = L["Config - Rings - Preview - Empty"] -- the empty text (SetRing shows it)
    preview.Empty:SetAlpha(0.75)

    -- Hide Hidden Actions: the eye in the top corner (remembered, for every menu).
    local eye = CreateFrame("Button", nil, host)
    eye:SetSize(EYE_SIZE, EYE_SIZE)
    eye:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PREVIEW_MARGIN, -PREVIEW_MARGIN)
    eye:SetFrameLevel(wheel:GetFrameLevel() + 12)
    eye.Texture = eye:CreateTexture(nil, "OVERLAY")
    eye.Texture:SetAllPoints()
    eye:SetScript("OnEnter", function(self)
        local key = IsHidingHidden() and "Config - Rings - Preview - HideHidden - On" or "Config - Rings - Preview - HideHidden - Off"
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L[key], 1, 1, 1)
        GameTooltip:AddLine(L[key .. " - Description"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    eye:SetScript("OnLeave", function() GameTooltip:Hide() end)
    eye:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Config.DBGlobal:SetVariable("PreviewHideHidden", not IsHidingHidden())
        preview:SetRing(preview.ring)
        if GameTooltip:GetOwner() == self then self:GetScript("OnEnter")(self) end
    end)
    preview.EyeButton = eye
    -- How many actions it leaves out right now, beside it.
    preview.EyeCount = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview.EyeCount:SetPoint("RIGHT", eye, "LEFT", -2, 1)
    preview.EyeCount:SetAlpha(0.75)
    preview:UpdateEyeButton(0)

    return preview
end
