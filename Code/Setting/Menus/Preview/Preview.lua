--[[
    Live wheel preview for the Menus tab: the same Menu_Layout wheel as the in-game menu.

    It behaves like the real menu while the mouse is over it, measured from the wheel's center.
    The pointer follows the cursor's angle, a wedge is picked by angle outside the dead zone, and
    the center highlights inside it. While the cursor is on an icon (or its X), that wedge stays
    selected, so the X is always reachable. The selected wedge shows a small X, and clicking it
    removes the action. Hovering an icon also shows its name in a tooltip.

    Drag and drop. Each wedge's angle has a middle part ("over" the action) and edges ("between"
    actions). A gold wedge marks over, a gold divider line marks between, and a GameTooltip
    pointing out of the wheel from the target says what releasing will do.
        - From the game: a spell, item, toy, macro or mount on the cursor. Over an action replaces
          it, between two actions inserts it there (the gap before the first action adds at the
          end), and the center makes it a tap-only quick action. On an empty menu, anywhere outside
          the center adds it. It works with drag and release, or pick up then click.
        - Reorder: press on an action's icon and drag (the icon follows the cursor). Over another
          action swaps the two, between two actions moves it there, and the center copies it there
          (it stays on the wheel, and replaces what the center had). Releasing off the wheel
          cancels.
        - Quick action: the center is a slot. Press on it and drag its action onto the wheel. Over
          an action swaps the two (not with a submenu or action bar, which can't be in the center),
          and between two actions inserts it there. An empty center drags out as a Close action (it
          cancels, like Close). The drag label says when an action can't go in the center.

    Double-click on the center cycles empty (Close Menu), a Last Used action and a First Action.
    Another quick action is only cleared with the center's X. Double-click on a submenu switches
    it between scroll and spread.

    The center icon is like the real menu before the mouse moves: the quick action's icon (a Last
    Used action shows the question mark here, and the last action's icon in game), or cancel when
    empty. The center's badges and X follow the quick action.

    Read-only (library menus, which fill themselves): actions can be rearranged by dragging and
    removed with the X (remembered, see Menu_Data Library.lua), but there's no "+" and nothing can
    be dropped in from the game.

    A menu with one action shows that action in the center instead (hover, X, tooltip and drag
    work on it there, since they follow the icon).

    Another class's or character's submenu (inside an account menu) counts as hidden: it doesn't
    exist on this character, so it has nothing to show (its name and icon come from that menu's
    saved copy, Elsewhere.lua; its tooltip says whose it is).

    Hide Hidden Actions (the eye in the top corner, PreviewHideHidden) leaves out the actions
    hidden in game right now too. The wheel's indexes are then positions among the shown actions
    (self.shown[index] = stored index), and the callbacks translate them back (StoredCallbacks),
    so edits still work. An action placed between two shown actions lands right before the second
    one, after any hidden actions in between.

    The files (one module, Menus_Preview, with shared state on the preview object and helpers in
    "@\\Setting\\Menus\\Preview\\Private"):
        Preview.lua     this file, building the preview (SetMenu, SetReadOnly)
        Display.lua     what it shows: selection, drop target, drag labels, tooltips, the gap "+"
        Input.lua       what it does: hit testing, hover, press, drag, drop, double-click
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Menu_Layout = env.AX_Modules:Await("@\\Menu\\Layout")
local Menu_Live = env.AX_Modules:Await("@\\Menu\\Live")
local UIFont = env.AX_Modules:Import("ax_modules\\ui-font")
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Text = UIKit.UI.Frames[5]
local UICCommon = env.AX_Modules:Import("ax_modules\\uic-common")
local GenericEnum = env.AX_Modules:Import("ax_modules\\generic-enum")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Utils_ConsolePort = env.AX_Modules:Import("@\\Utils\\ConsolePort")
local Menus_Preview = env.AX_Modules:New("@\\Setting\\Menus\\Preview")
local Private = env.AX_Modules:New("@\\Setting\\Menus\\Preview\\Private")

local PREVIEW_SCALE = 1 -- the same size as the in-game menu at the default Menu Size
local REMOVE_SIZE = 20
-- The X's center sits this far in from the corner, minus half its size (2px inside the icon).
local REMOVE_OFFSET = 12
local REMOVE_ALPHA = 0.8 -- full while hovered
local QUICK_REMOVE_SCALE = 0.8 -- the center icon is smaller than an action's
local DRAG_ICON_SIZE = 36
local INSERT_LINE_COLOR = { 1, 0.82, 0, 0.95 }
local INSERT_LINE_THICKNESS = 4
-- The X sits above the icons, and the gap "+" and the eye above that, over the wheel.
local REMOVE_FRAME_LEVEL = 10
local CONTROL_FRAME_LEVEL = 12
-- The empty menu's text, below the center.
local EMPTY_TEXT_Y = -70
local EMPTY_TEXT_WIDTH = 240
local MUTED_ALPHA = 0.75 -- the empty text and the hidden count
local EYE_OFF_ALPHA = 0.6 -- the eye while hidden actions are shown
-- The "+" on the gap between two actions (hovered), to add an action at that spot.
local GAP_BUTTON_SIZE = 26
local GAP_BUTTON_RADIUS = 128
Private.GAP_BUTTON_SIZE, Private.GAP_BUTTON_RADIUS = GAP_BUTTON_SIZE, GAP_BUTTON_RADIUS

-- It fits what you interact with (icons and the gap "+", out to GAP_BUTTON_RADIUS), not the whole
-- wheel art. The faded background and highlight wedges may reach a little past it.
local PREVIEW_MARGIN = 6
Menus_Preview.HEIGHT = math.ceil(2 * (GAP_BUTTON_RADIUS + GAP_BUTTON_SIZE / 2) * PREVIEW_SCALE) + 2 * PREVIEW_MARGIN
local EYE_SIZE = 24

-- Where a drag or drop would land (PreviewMixin:GetDropTarget's `mode`).
Private.Target = Utils_Standard.Strict({
    Center  = "center",  -- the dead zone: the quick action
    Over    = "over",    -- on an action
    Between = "between", -- between two actions, on their divider
    Add     = "add",     -- anywhere on an empty menu
}, "preview drop target")
-- The center, as a tooltip index or a press (besides wedge indexes).
Private.CENTER = "center"
-- The quick action, as what's dragged (besides wedge indexes).
Private.QUICK = "quick"
-- Straight down from the wheel center, in radians. Tooltips from the center open this way.
Private.BELOW = -math.pi / 2


---@class PreviewEyeButton : Button
---@field Texture Texture

--- The settings preview (Menus_Preview.Create). Display.lua and Input.lua add methods.
---@class MenuPreview
---@field wheel MenuWheel
---@field menu Menu? the menu shown
---@field shown integer[] the stored index of each wedge (Hide Hidden Actions leaves some out)
---@field callbacks table the edits, with wheel positions turned into stored indexes
---@field readOnly boolean a library menu, rearranged and trimmed but not added to
---@field locked boolean another class's or character's menu, look only
---@field emptyText string
---@field selectedIndex integer?
---@field tooltipIndex integer|string|nil a wedge index or Private.CENTER
---@field tooltipOwner Frame?
---@field drag table? the drag in progress (BeginDrag)
---@field lastPressIndex integer|string|nil for double-clicks, a wedge index or Private.CENTER
---@field lastPressTime number
---@field QuickRemove Button the center's X
---@field DragIcon ActionIcon
---@field GapButton table the gap "+" (insertIndex, tooltipAngle)
---@field InsertLine Line
---@field LabelAnchor Frame
---@field Empty FontString
---@field EyeButton PreviewEyeButton
---@field EyeCount FontString
local PreviewMixin = {}
Private.PreviewMixin = PreviewMixin

--- The stored action at wheel position `index` (Hide Hidden Actions leaves some out).
---@param index integer?
---@return Action?
function PreviewMixin:GetAction(index)
    local stored = index and self.shown[index]
    return stored and self.menu.actions[stored]
end

--- What wheel position `index` shows (a scroll submenu shows its current action).
---@param index integer?
---@return Action?
function PreviewMixin:GetShownAction(index)
    local stored = index and self.shown[index]
    return stored and Menu_Live.GetStoredShownAction(self.menu, stored)
end

--- The callbacks with wheel positions turned back into stored indexes (the others are passed
--- through). A gap position (insert so the new action becomes #index) goes right before that
--- shown action, or at the end past the last.
---@param preview MenuPreview
---@param callbacks table
---@return table
local function StoredCallbacks(preview, callbacks)
    local function Stored(index) return index and preview.shown[index] end
    local function Gap(index) return index and (preview.shown[index] or #preview.menu.actions + 1) end
    local function Call(name, ...)
        if callbacks[name] then return callbacks[name](...) end
    end
    return setmetatable({
        onAdd             = function(index) return Call("onAdd", Gap(index)) end,
        onRemove          = function(index) return Call("onRemove", Stored(index)) end,
        onToggleSpread    = function(index) return Call("onToggleSpread", Stored(index)) end,
        onQuickFromAction = function(index) return Call("onQuickFromAction", Stored(index)) end,
        onQuickToWheel    = function(index, replace) return Call("onQuickToWheel", replace and Stored(index) or Gap(index), replace) end,
        onSwap            = function(a, b) return Call("onSwap", Stored(a), Stored(b)) end,
        onDrop            = function(action, index) return Call("onDrop", action, Gap(index)) end,
        onReplace         = function(index, action) return Call("onReplace", Stored(index), action) end,
        -- `to` is its position once taken out: the gap it was dropped into, before removal.
        onMove           = function(from, to)
            local fromStored, gap = Stored(from), Gap(to >= from and to + 1 or to)
            return Call("onMove", fromStored, gap > fromStored and gap - 1 or gap)
        end,
    }, { __index = callbacks })
end

--- Whether Hide Hidden Actions is on.
---@return boolean
local function IsHidingHidden()
    return Config.DBGlobal and Config.Get(Config.Key.PreviewHideHidden) and true or false
end

--- The X on an icon's top-right corner.
---@param preview MenuPreview
---@param wedge table a MenuWedge, or { Button = the center's icon }
---@param onClick function? removing the wedge's action by default
---@return Button
local function CreateRemoveButton(preview, wedge, onClick)
    local button = CreateFrame("Button", nil, wedge.Button)
    button:SetSize(REMOVE_SIZE, REMOVE_SIZE)
    button:SetPoint("CENTER", wedge.Button, "TOPRIGHT", -REMOVE_OFFSET + REMOVE_SIZE / 2, -REMOVE_OFFSET + REMOVE_SIZE / 2)
    button:SetFrameLevel(preview.wheel:GetFrameLevel() + REMOVE_FRAME_LEVEL)

    button.Texture = button:CreateTexture(nil, "OVERLAY")
    button.Texture:SetAllPoints()
    button.Texture:SetAtlas(Menu_Layout.ATLAS_CANCEL_ICON)
    button:SetAlpha(REMOVE_ALPHA)

    button:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    button:SetScript("OnLeave", function(self) self:SetAlpha(REMOVE_ALPHA) end)
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



--- Whether the menu shown is read-only (a library menu), so it can't be added to from the wheel.
---@param readOnly boolean
---@param libraryKey string? the library menu's key, for its "nothing here yet" text
function PreviewMixin:SetReadOnly(readOnly, libraryKey)
    self.readOnly = readOnly or false
    -- "Config - Menus - Auto - Empty - <key>", one per library menu (LibraryDefinition.key).
    local emptyText = self.readOnly and L["Config - Menus - Auto - Empty - " .. tostring(libraryKey)]
    self.emptyText = emptyText or L["Config - Menus - Preview - Empty"] -- shown by SetMenu
end

--- Whether the menu shown is locked (another class's or character's menu), look only. Unlike
--- read-only (a library menu, rearranged and trimmed but not added to), nothing changes it: no
--- drags, X, double-clicks or drops.
---@param locked boolean
function PreviewMixin:SetLocked(locked)
    self.locked = locked or false
    if self.locked then self.readOnly = true end
end

--- Redraws the wheel for `menu` (nil clears it).
---@param menu Menu?
function PreviewMixin:SetMenu(menu)
    self:EndDrag(false)
    self.menu = menu
    self.selectedIndex = nil
    self.tooltipIndex = nil
    if self.tooltipOwner and GameTooltip:GetOwner() == self.tooltipOwner then GameTooltip:Hide() end
    self.tooltipOwner = nil

    local wheel = self.wheel
    -- The actions on the wheel: all of them, or (Hide Hidden Actions) the ones shown in game now.
    -- Another class's or character's submenu counts as hidden, since it doesn't exist here and so
    -- has nothing to show (its tooltip says whose it is).
    local hideHidden = IsHidingHidden()
    self.shown = {}
    local actions, hiddenCount = {}, 0
    for index, action in ipairs(menu and menu.actions or {}) do
        if hideHidden and not Menu_Actions.IsActionAvailable(action) then
            hiddenCount = hiddenCount + 1
        else
            self.shown[#self.shown + 1] = index
            actions[#actions + 1] = action
        end
    end
    self:UpdateEyeButton(hiddenCount)
    -- Scroll submenus show their current action, like the in-game menu.
    local displayActions = {}
    for index = 1, #actions do
        displayActions[index] = self:GetShownAction(index)
    end
    local hasTapOnly = menu ~= nil and Menu_Data.GetQuickAction(menu) ~= nil
    wheel:SetActions(displayActions, nil, hasTapOnly)
    -- Scroll submenus show what scrolls them in game, the D-pad when playing with a controller.
    wheel:SetScrollBadges(actions, nil, env.IsGamepadUI() or Utils_ConsolePort.IsActive())
    wheel:SetConditionBadges(actions)
    for i = 1, #wheel.Wedges do
        local wedge = wheel.Wedges[i]
        wedge.Button:SetAlpha(1)
        if wedge.RemoveButton then wedge.RemoveButton:Hide() end
    end
    wheel:SetPointerAngle(nil)

    local quickIcon, quickAction
    if #actions == 0 then
        quickIcon = nil -- nothing to fire yet, so it shows cancel
    elseif menu then
        quickAction = Menu_Data.GetQuickAction(menu)
        -- With Hide Hidden Actions, a hidden quick action leaves the center to cancel, like in game.
        if hideHidden and quickAction and not Menu_Actions.IsActionAvailable(quickAction) then quickAction = nil end
        quickIcon = quickAction and Menu_Actions.GetIcon(quickAction)
    end
    wheel:SetQuickIcon(quickIcon, quickAction)
    -- A single action sits in the center and is itself the quick action, unless a tap-only quick
    -- action owns the center (Menu_Layout, Menu_Secure).
    wheel:SetCenter(quickIcon ~= nil or wheel.isSingleCentered, false)
    wheel:SetQuickBadges(self:GetQuickStoredAction())
    wheel:SetCenterHighlight(false)

    -- Nothing on the wheel means an empty menu, or (Hide Hidden Actions) all of it hidden now.
    local allHidden = #actions == 0 and hiddenCount > 0
    self.Empty:SetText(allHidden and L["Config - Menus - Preview - AllHidden"] or self.emptyText)
    self.Empty:SetShown(#actions == 0)
    self:SetGapTarget(nil) -- places the "+" on an empty menu, hides it otherwise
end

--- Shows the eye toggle's current state: crossed out while hidden actions are left out, with how
--- many are beside it.
---@param hiddenCount integer
function PreviewMixin:UpdateEyeButton(hiddenCount)
    local hiding = IsHidingHidden()
    local atlas = Menu_Layout.GetEyeAtlas(hiding)
    if atlas then self.EyeButton.Texture:SetAtlas(atlas) end
    self.EyeButton:SetAlpha(hiding and 1 or EYE_OFF_ALPHA)
    local count = hiding and hiddenCount or 0
    self.EyeCount:SetText(count > 0 and format(L["Config - Menus - Preview - HiddenCount"], count) or "")
end

--- A new preview, centered in `host`.
---@param host Frame the frame to center the wheel in (at least Menus_Preview.HEIGHT tall)
---@param callbacks table what edits do. The ones marked "returns ok" say whether it worked.
---     onAdd(index)                     the "+" on a gap was clicked (insert so the new action is #index)
---     onRemove(index)                  an action's X was clicked
---     onToggleSpread(index)            a submenu was double-clicked (switch scroll and spread)
---     onSetQuick(action)               dropped from the game onto the center, returns ok
---     onQuickFromAction(index)         an action was dragged onto the center (the quick action is it)
---     onQuickToWheel(index, replace)   the tap-only quick action was dragged onto the wheel
---     onToggleQuick()                  the center was double-clicked (cycle the quick action)
---     onClearQuick()                   the center's X was clicked (no quick action)
---     onSwap(a, b)                     an action was dragged onto another action
---     onMove(from, to)                 an action was dragged between two actions (ends up at `to`)
---     onDrop(action, index)            dropped from the game between actions (index nil adds it at
---                                      the end), returns ok
---     onReplace(index, action)         dropped from the game onto an action, returns ok
---@return MenuPreview
function Menus_Preview.Create(host, callbacks)
    local preview = CreateFromMixins(PreviewMixin)
    preview.callbacks = StoredCallbacks(preview, callbacks or {})
    preview.shown = {}

    local wheel = Menu_Layout.CreateWheel(host)
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

    -- The X on the center, which clears the quick action.
    preview.QuickRemove = CreateRemoveButton(preview, { Button = wheel.Quick }, function()
        if preview.callbacks.onClearQuick then preview.callbacks.onClearQuick() end
    end)
    preview.QuickRemove:SetScale(QUICK_REMOVE_SCALE)

    -- The icon that follows the cursor while reordering.
    preview.DragIcon = Menu_Layout.CreateActionIcon(UIParent, DRAG_ICON_SIZE)
    preview.DragIcon:SetFrameStrata("TOOLTIP")
    preview.DragIcon:Hide()

    -- The "+" on a hovered gap between two actions, which opens Add Action to insert there. It's
    -- the same red button art as "+ Add Action", in its square variant.
    local gap = UICCommon.ButtonRedSquare("RLRM_MenuPreview.GapButton", {
        Text("RLRM_MenuPreview.GapButton.Text")
            :id("GapText", "RLRM_MenuPreview.GapButton")
            :fontObject(UIFont.UIFontObjectNormal14)
            :textColor(GenericEnum.UIColorRGB.NormalText)
            :textAlignment("CENTER", "MIDDLE")
            :size(UIKit.UI.FILL)
    })
        :parent(wheel)
        :size(GAP_BUTTON_SIZE, GAP_BUTTON_SIZE)
    gap.Text = UIKit.GetElementById("GapText", "RLRM_MenuPreview.GapButton")
    gap.Text:SetText("+")
    gap:SetFrameLevel(wheel:GetFrameLevel() + CONTROL_FRAME_LEVEL)
    gap:HookMouseEnter(function(self)
        Private.SetTooltipOutward(self, self.tooltipAngle or Private.BELOW)
        GameTooltip:SetText(L["Config - Menus - AddAction"], 1, 1, 1)
        GameTooltip:Show()
    end)
    gap:HookMouseLeave(function() GameTooltip:Hide() end)
    gap:HookClick(function(self)
        if preview.callbacks.onAdd then preview.callbacks.onAdd(self.insertIndex) end
    end)
    gap:_Render()
    gap:Hide()
    preview.GapButton = gap

    -- The gold line on the divider where an action would be inserted.
    preview.InsertLine = wheel:CreateLine(nil, "OVERLAY", nil, 5)
    preview.InsertLine:SetThickness(INSERT_LINE_THICKNESS)
    preview.InsertLine:SetColorTexture(unpack(INSERT_LINE_COLOR))
    preview.InsertLine:Hide()

    -- An invisible anchor for the drag label (Swap, Move here, Replace, Insert, Add to end) on a
    -- divider or the center. Over an action, it anchors to the action's icon.
    preview.LabelAnchor = CreateFrame("Frame", nil, wheel)
    preview.LabelAnchor:SetSize(GAP_BUTTON_SIZE, GAP_BUTTON_SIZE)

    preview.Empty = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    preview.Empty:SetPoint("CENTER", wheel, "CENTER", 0, EMPTY_TEXT_Y)
    preview.Empty:SetWidth(EMPTY_TEXT_WIDTH)
    preview.emptyText = L["Config - Menus - Preview - Empty"] -- the empty text (SetMenu shows it)
    preview.Empty:SetAlpha(MUTED_ALPHA)

    -- The Hide Hidden Actions eye in the top corner (remembered, for every menu).
    local eye = CreateFrame("Button", nil, host) --[[@as PreviewEyeButton]]
    eye:SetSize(EYE_SIZE, EYE_SIZE)
    eye:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PREVIEW_MARGIN, -PREVIEW_MARGIN)
    eye:SetFrameLevel(wheel:GetFrameLevel() + CONTROL_FRAME_LEVEL)
    eye.Texture = eye:CreateTexture(nil, "OVERLAY")
    eye.Texture:SetAllPoints()
    eye:SetScript("OnEnter", function(self)
        -- "Config - Menus - Preview - HideHidden - On" or "- Off", each with a " - Description".
        local key = IsHidingHidden() and "Config - Menus - Preview - HideHidden - On" or "Config - Menus - Preview - HideHidden - Off"
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L[key], 1, 1, 1)
        GameTooltip:AddLine(L[key .. " - Description"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    eye:SetScript("OnLeave", function() GameTooltip:Hide() end)
    eye:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Config.Set(Config.Key.PreviewHideHidden, not IsHidingHidden())
        preview:SetMenu(preview.menu)
        if GameTooltip:GetOwner() == self then self:GetScript("OnEnter")(self) end
    end)
    preview.EyeButton = eye
    -- How many actions it leaves out right now, beside it.
    preview.EyeCount = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview.EyeCount:SetPoint("RIGHT", eye, "LEFT", -2, 1)
    preview.EyeCount:SetAlpha(MUTED_ALPHA)
    preview:UpdateEyeButton(0)

    return preview
end
