--[[
    List tabs: a tab whose sidebar entry is a list of selectable items (profiles, groups, ...),
    each opening the tab's page for that item.

        nav = Setting.AttachListNav(tab, {
            sections = {                                -- top to bottom
                {
                    title     = "Pinned",               -- section header (the first one is the tab's
                                                        --   own button, shown as a header)
                    visible   = 2,                      -- items shown before it scrolls; leave out on
                                                        --   the last section to fill the rest
                    newButton = { text = "+ New", onClick = function() end },   -- optional
                    actions   = {                       -- optional: a row of equal buttons (newButton's
                        { text = "Import", onClick = function() end },  -- look) under newButton;
                        ...                             --   the tab opens after onClick
                    },
                    getItems  = function() return { { id, title, left, right }, ... } end,
                },
                ...
            },
            getSelected = function() return itemId end,  -- highlighted while the tab is open
            onSelect    = function(itemId) end,          -- an item was clicked (the tab then opens)
        })

        nav:Refresh()         -- items or selection changed
        nav:Select(itemId)    -- select from code (onSelect, open the tab, refresh)

    Call it from the tab's Custom widget builder (it gets the tab). The list fills the sidebar
    below the tab's button, so the list tab should be the last tab above the footer.
]]

local env = select(2, ...)
local Sound = env.AX_Modules:Import("ax_modules\\sound")
local UIFont = env.AX_Modules:Import("ax_modules\\ui-font")
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Frame, _, LayoutHorizontal, LayoutVertical, Text, ScrollView = unpack(UIKit.UI.Frames)
local UICSharedMixin = env.AX_Modules:Import("ax_modules\\uic-sharedmixin")
local UICCommon = env.AX_Modules:Import("ax_modules\\uic-common")
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Setting = env.AX_Modules:Import("@\\Setting")
local Setting_Constructor = env.AX_Modules:Import("@\\Setting\\Constructor")
local Setting_ListNav = env.AX_Modules:New("@\\Setting\\ListNav")

local tinsert = table.insert

local NAV_INDENT = 12        -- cards and buttons are indented; the scroll bar sits in the gap
local CARD_HEIGHT = 40
local CARD_SPACING = 3
local CARD_RIGHT_WIDTH = 64  -- the detail line's right-hand text; the left text stops short of it
local NEW_BUTTON_HEIGHT = 28
local NEW_BUTTON_GAP = 8
local ACTION_HEIGHT = 28     -- the row of action buttons under newButton
local ACTION_SPACING = 6
local SCROLLBAR_WIDTH = 6
local SECTION_GAP = 4        -- between a section's list and the next section's header
-- The sidebar reserves 75px at the bottom for the footer, but a footer tab only uses ~35px.
local NAV_FOOTER_OVERLAP = 32
-- Sidebar tab buttons (Setting_Widgets.TabButton) and the sidebar's layout spacing (Setting_UI).
local SIDEBAR_TAB_HEIGHT = 35
local SIDEBAR_SPACING = 3
-- Headers look like an unselected tab button (Setting_Widgets TabButton TEXT_COLOR / TEXT_ALPHA).
local HEADER_TEXT_COLOR = UIKit.Define.Color_RGBA{ r = 255, g = 255, b = 255, a = 1 }
local HEADER_TEXT_ALPHA = 0.5

local SettingFrame = _G[Setting_Preload.FRAME_NAME]



-- Card (tab button look: gold when selected)

local CardMixin = CreateFromMixins(UICSharedMixin.ButtonMixin)

function CardMixin:OnLoad()
    self:InitButton()
    self.isSelected = false
    self.itemId = nil

    self:RegisterMouseEvents()
    self:HookButtonStateChange(self.UpdateAnimation)
    self:HookClick(self.OnCardClick)
    self:HookMouseEnter(self.ShowFullText)
    self:HookMouseLeave(function(card) if GameTooltip:GetOwner() == card then GameTooltip:Hide() end end)
    self:UpdateAnimation()
end

--- Hovered: when any of the card's text is cut off ("..."), a tooltip shows all of it.
function CardMixin:ShowFullText()
    if not (self.Title:IsTruncated() or self.Left:IsTruncated() or self.Right:IsTruncated()) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.Title:GetText() or "", 1, 1, 1)
    local left, right = self.Left:GetText(), self.Right:GetText()
    if (left and left ~= "") or (right and right ~= "") then
        GameTooltip:AddDoubleLine(left or "", right or "", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

function CardMixin:OnCardClick()
    Sound.PlaySound("UI", SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if self.onSelect then self.onSelect(self.itemId) end
end

function CardMixin:SetSelected(selected)
    self.isSelected = selected
    self:UpdateAnimation()
end

function CardMixin:UpdateAnimation()
    local state = self:GetButtonState()
    local UIDef = Setting_Preload.UIDef
    local texture
    if self.isSelected then
        texture = (state == "PUSHED" and UIDef.UITabButtonSelected_Pushed)
            or (state == "HIGHLIGHTED" and UIDef.UITabButtonSelected_Highlighted)
            or UIDef.UITabButtonSelected
    else
        texture = (state == "PUSHED" and UIDef.UITabButton_Pushed)
            or (state == "HIGHLIGHTED" and UIDef.UITabButton_Highlighted)
            or UIDef.UITabButton
    end
    self.Background:background(texture)
    self.Info:SetAlpha((self.isSelected or state ~= "NORMAL") and 1 or 0.6)
end

--- Title, and a detail line with text on the left and on the right. Text that doesn't fit is cut
--- off with "..."; hovering the card then shows all of it (ShowFullText).
local Card = UIKit.Template(function(id, name, children, ...)
    local frame =
        Frame(name, {
            Frame(name .. ".Background")
                :id("Background", id)
                :size(UIKit.Define.Fill{ delta = -7 })
                :background(UIKit.UI.TEXTURE_NIL)
                :frameLevel(1)
                :_excludeFromCalculations(),

            LayoutVertical(name .. ".Info", {
                Text(name .. ".Title")
                    :id("Title", id)
                    :fontObject(UIFont.UIFontObjectNormal12)
                    :textAlignment("LEFT", "MIDDLE")
                    :size(UIKit.UI.P_FILL, 14),

                Frame(name .. ".Detail", {
                    Text(name .. ".Detail.Left")
                        :id("Left", id)
                        :fontObject(UIFont.UIFontObjectNormal11)
                        :textAlignment("LEFT", "MIDDLE")
                        :point(UIKit.Enum.Point.Left)
                        :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = CARD_RIGHT_WIDTH + 4 }, 12),

                    Text(name .. ".Detail.Right")
                        :id("Right", id)
                        :fontObject(UIFont.UIFontObjectNormal11)
                        :textAlignment("RIGHT", "MIDDLE")
                        :point(UIKit.Enum.Point.Right)
                        :size(CARD_RIGHT_WIDTH, 12)
                })
                    :alpha(0.6)
                    :size(UIKit.UI.P_FILL, 12)
            })
                :id("Info", id)
                :point(UIKit.Enum.Point.Left)
                :x(14)
                :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = 28 }, UIKit.Define.Fit{})
                :layoutSpacing(2)
                :frameLevel(2)
        })
        :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = NAV_INDENT }, CARD_HEIGHT)

    frame.Background = UIKit.GetElementById("Background", id)
    frame.Info = UIKit.GetElementById("Info", id)
    frame.Title = UIKit.GetElementById("Title", id)
    frame.Left = UIKit.GetElementById("Left", id)
    frame.Right = UIKit.GetElementById("Right", id)

    Mixin(frame, CardMixin)
    frame:OnLoad()

    return frame
end)



-- Nav

--- Section header drawn like a tab button used as a header (35px row, 12pt text, white at 50%).
local function SectionHeader(name, id, textId)
    return Frame(name, {
        Text(name .. ".Text")
            :id(textId, id)
            :point(UIKit.Enum.Point.Center)
            :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = 23 }, UIKit.Define.Percentage{ value = 100, operator = "-", delta = 23 })
            :fontObject(UIFont.UIFontObjectNormal12)
            :textColor(HEADER_TEXT_COLOR)
            :alpha(HEADER_TEXT_ALPHA)
            :textAlignment("LEFT", "MIDDLE")
    })
        :size(UIKit.UI.P_FILL, SIDEBAR_TAB_HEIGHT)
end

--- Scrolling card list with its own scroll bar in the indent gap on the left.
local function CardList(name, id, key, height)
    return
        ScrollView(name, {
            LayoutVertical(name .. ".Cards")
                :id(key .. "Cards", id)
                :point(UIKit.Enum.Point.Top)
                :size(UIKit.UI.P_FILL, UIKit.Define.Fit{})
                :layoutSpacing(CARD_SPACING)
                :layoutAlignmentH(UIKit.Enum.Direction.Trailing)
                :_updateMode(UIKit.Enum.UpdateMode.ChildrenVisibilityChanged)
        })
            :id(key .. "Scroll", id)
            :size(UIKit.UI.P_FILL, height)
            :scrollViewContentWidth(UIKit.UI.P_FILL)
            :scrollViewContentHeight(UIKit.Define.Fit{})
            :layoutDirection(UIKit.Enum.Direction.Vertical)
            :scrollStepSize(CARD_HEIGHT + CARD_SPACING) -- one card per wheel step (the default is 150px)
            :scrollInterpolation(10),

        UICCommon.ScrollBar(name .. ".ScrollBar")
            :id(key .. "ScrollBar", id)
            :x(1)
            :size(SCROLLBAR_WIDTH, height)
            :linkedScrollView(UIKit.NewGroupCaptureString(key .. "Scroll", id))
end

--- Hides a list's scroll bar (track too) while the list fits. Alpha rather than Hide so UIKit
--- renders don't show it again, and no mouse so the invisible track can't be clicked.
local function AutoHideScrollBar(scrollBar, scroll, cards)
    hooksecurefunc(scrollBar, "SetThumbVisible", function(bar, isVisible)
        bar:SetAlpha(isVisible and 1 or 0)
        bar:EnableMouse(isVisible)
    end)
    scrollBar:SetAlpha(0)
    scrollBar:EnableMouse(false)

    -- Re-check when items are added / removed or the sidebar resizes, not only on scroll.
    local function Sync() scrollBar:SyncValue() end
    cards:HookScript("OnSizeChanged", Sync)
    scroll:HookScript("OnSizeChanged", Sync)
end

--- The sections, top to bottom, below the tab's button. The first section's header is that button.
--- @param aboveHeight number height taken by the tab buttons above (and including) the list tab
local Nav = UIKit.Template(function(id, name, children, aboveHeight, sections)
    local elements = {}
    local y = 0
    for index, section in ipairs(sections) do
        local key = "S" .. index
        if index > 1 then
            y = y - SECTION_GAP
            tinsert(elements, SectionHeader(name .. ".Header" .. index, id, key .. "Header")
                :point(UIKit.Enum.Point.Top)
                :y(y))
            y = y - SIDEBAR_TAB_HEIGHT
        end
        if section.newButton then
            tinsert(elements, UICCommon.ButtonRedWithText(name .. ".New" .. index)
                :id(key .. "New", id)
                :point(UIKit.Enum.Point.TopRight)
                :y(y)
                :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = NAV_INDENT }, NEW_BUTTON_HEIGHT))
            y = y - NEW_BUTTON_HEIGHT - NEW_BUTTON_GAP
        end
        if section.actions and #section.actions > 0 then
            local buttons = {}
            local count = #section.actions
            for actionIndex in ipairs(section.actions) do
                buttons[actionIndex] = UICCommon.ButtonRedWithText(name .. ".Action" .. index .. "_" .. actionIndex)
                    :id(key .. "Action" .. actionIndex, id)
                    :size(UIKit.Define.Percentage{ value = 100 / count, operator = "-", delta = ACTION_SPACING * (count - 1) / count }, ACTION_HEIGHT)
            end
            tinsert(elements, LayoutHorizontal(name .. ".Actions" .. index, buttons)
                :point(UIKit.Enum.Point.TopRight)
                :y(y)
                :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = NAV_INDENT }, ACTION_HEIGHT)
                :layoutSpacing(ACTION_SPACING))
            y = y - ACTION_HEIGHT - NEW_BUTTON_GAP
        end

        local height
        if section.visible then
            height = section.visible * CARD_HEIGHT + (section.visible - 1) * CARD_SPACING
        else
            assert(index == #sections, "AX_Settings: only the last list section can fill the sidebar")
            height = UIKit.Define.Percentage{ value = 100, operator = "-", delta = -y }
        end
        local scroll, scrollBar = CardList(name .. ".List" .. index, id, key, height)
        tinsert(elements, scroll:point(UIKit.Enum.Point.Top):y(y))
        tinsert(elements, scrollBar:point(UIKit.Enum.Point.TopLeft):y(y))
        if section.visible then y = y - height end
    end

    local frame =
        Frame(name, elements)
            :size(UIKit.UI.P_FILL, UIKit.Define.Percentage{ value = 100, operator = "-", delta = aboveHeight - NAV_FOOTER_OVERLAP })

    frame.sections = {}
    for index, section in ipairs(sections) do
        local key = "S" .. index
        local refs = {
            header = index > 1 and UIKit.GetElementById(key .. "Header", id) or nil,
            newButton = section.newButton and UIKit.GetElementById(key .. "New", id) or nil,
            actions = {},
            scroll = UIKit.GetElementById(key .. "Scroll", id),
            cards = UIKit.GetElementById(key .. "Cards", id),
            pool = {}
        }
        for actionIndex in ipairs(section.actions or {}) do
            refs.actions[actionIndex] = UIKit.GetElementById(key .. "Action" .. actionIndex, id)
        end
        AutoHideScrollBar(UIKit.GetElementById(key .. "ScrollBar", id), refs.scroll, refs.cards)
        frame.sections[index] = refs
    end
    return frame
end)

local NavMixin = {}

function NavMixin:GetCard(sectionIndex, index)
    local refs = self.sections[sectionIndex]
    local card = refs.pool[index]
    if not card then
        card = Card(self.cardPrefix .. sectionIndex .. "_" .. index)
        card:parent(refs.cards)
        card.onSelect = function(itemId) self:Select(itemId) end
        card:_Render()
        refs.pool[index] = card
    end
    return card
end

--- Rebuilds the cards from getItems and shows the selection (only while the tab is open, so it
--- doesn't compete with another selected tab).
function NavMixin:Refresh()
    local selected = self.spec.getSelected and self.spec.getSelected()
    local tabOpen = self.tab:IsShown()
    for sectionIndex, section in ipairs(self.spec.sections) do
        local items = section.getItems() or {}
        local pool = self.sections[sectionIndex].pool
        for index, item in ipairs(items) do
            local card = self:GetCard(sectionIndex, index)
            card.itemId = item.id
            card.Title:SetText(item.title or "")
            card.Left:SetText(item.left or "")
            card.Right:SetText(item.right or "")
            card:SetSelected(tabOpen and item.id == selected)
            card:Show()
        end
        for index = #items + 1, #pool do
            pool[index]:Hide()
        end
    end
    self:_Render()
end

--- Selects `itemId`: tells the addon, opens the tab if another one is showing, refreshes.
function NavMixin:Select(itemId)
    if self.spec.onSelect then self.spec.onSelect(itemId) end
    if not self.tab:IsShown() then Setting:OpenTabByIndex(self.tabIndex) end
    self:Refresh()
end

--- See the header comment.
function Setting_ListNav.Attach(tab, spec)
    local tabIndex
    for index, other in ipairs(Setting_Constructor.Tabs) do
        if other == tab then tabIndex = index end
    end
    assert(tabIndex, "AX_Settings: AttachListNav needs a tab built from the schema")
    assert(spec.sections and #spec.sections > 0, "AX_Settings: AttachListNav needs sections")

    -- The tab's button is the first section's header: no background, no highlight, not clickable
    -- (the items below it are the way into the tab).
    local header = Setting_Constructor.TabButtons[tabIndex]
    header:SetText(spec.sections[1].title or "")
    function header:UpdateAnimation()
        self.Background:background(UIKit.UI.TEXTURE_NIL)
        self.Text:ClearAllPoints()
        self.Text:SetPoint("CENTER", self, 0, 0)
        self.Text:textColor(HEADER_TEXT_COLOR)
        self.Text:SetAlpha(HEADER_TEXT_ALPHA)
    end
    header:EnableMouse(false)
    header:UpdateAnimation()

    -- Tab buttons up to this one sit above the list (footer tabs are separate).
    local aboveHeight = tabIndex * (SIDEBAR_TAB_HEIGHT + SIDEBAR_SPACING)
    local name = Setting_Preload.FRAME_NAME .. ".ListNav" .. tabIndex
    local nav = Nav(name, nil, aboveHeight, spec.sections)
    Mixin(nav, NavMixin)
    nav.spec, nav.tab, nav.tabIndex, nav.cardPrefix = spec, tab, tabIndex, name .. ".Card"

    for index, section in ipairs(spec.sections) do
        local refs = nav.sections[index]
        if refs.header then refs.header:SetText(section.title or "") end
        if refs.newButton then
            refs.newButton:SetText(section.newButton.text or "")
            refs.newButton:HookClick(function() section.newButton.onClick() end)
        end
        for actionIndex, action in ipairs(section.actions or {}) do
            local button = refs.actions[actionIndex]
            button:SetText(action.text or "")
            button:HookClick(function()
                if action.onClick then action.onClick() end
                if not tab:IsShown() then Setting:OpenTabByIndex(tabIndex) end
                nav:Refresh()
            end)
        end
    end

    nav:parent(SettingFrame.Sidebar.Tab)
    SettingFrame.Sidebar.Tab:_Render()
    nav:_Render()

    -- The list's height is a percentage of the sidebar, which only gets its real size once the
    -- settings frame renders. Re-layout whenever the sidebar is resized. Deferred a frame:
    -- OnSizeChanged fires inside a UIKit render pass, and frames queued during a pass are dropped
    -- and then stay flagged as queued, so they would never render again.
    local renderPending = false
    SettingFrame.Sidebar.Tab:HookScript("OnSizeChanged", function()
        if renderPending then return end
        renderPending = true
        C_Timer.After(0, function()
            renderPending = false
            nav:_Render()
        end)
    end)

    tab:HookScript("OnShow", function() nav:Refresh() end)
    tab:HookScript("OnHide", function() nav:Refresh() end)
    return nav
end

Setting.AttachListNav = Setting_ListNav.Attach
