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
                    tabs      = {                       -- optional: a split button above newButton,
                        { id = "mine", text = "Mine" }, --   one part per tab, the selected one gold,
                        ...                             --   e.g. to switch what getItems returns
                    },
                    search    = { placeholder = "Search" },  -- optional: a search box under tabs
                                                               --   (above newButton): lists only
                                                               --   cards whose title (or a keyword)
                                                               --   has the text, under their groups
                                                               --   (shown open); Escape clears it
                    getTab    = function() return tabId end,  -- with tabs: the selected one
                    onTab     = function(tabId) end,           -- with tabs: one was clicked (the
                                                               --   list then refreshes)
                    getItems  = function() return { { id, title, left, right, muted }, ... } end,
                                                        -- muted: read-only look (dimmed, selectable);
                                                        -- keywords: { "text", ... } or a function
                                                        --   returning them (asked only while
                                                        --   searching), also matched by `search`;
                                                        -- { group = true, id, title, right, collapsed }:
                                                        --   a collapsible header for the items after
                                                        --   it (right: e.g. a count; collapsed: its
                                                        --   default, else expanded)
                },
                ...
            },
            getSelected = function() return itemId end,  -- highlighted while the tab is open
            onSelect    = function(itemId) end,          -- an item was clicked (the tab then opens)
            collapsed   = {},                            -- optional: [groupId] = true / false as the
                                                         --   user toggles groups (pass a saved table
                                                         --   to keep them between sessions)
            onGroupToggle = function(groupId, collapsed) end,  -- optional: a group was toggled
        })

        nav:Refresh()         -- items or selection changed
        nav:Select(itemId)    -- select from code (onSelect, open the tab, refresh, scroll to it)
        nav:ScrollTo(itemId)  -- scroll just enough to show its card
        nav:SetGroupCollapsed(groupId, collapsed, noRefresh)  -- from code, as a click on the group
                                                               --   row (noRefresh: you refresh next)

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
-- Group rows (items with `group = true`): a collapsible header inside a list, with a +/- icon as
-- its toggle: the character select screen's camp group icons (just the icon: the whole row is
-- clickable) where the game has them, else the quest log's +/- buttons (in every client).
local GROUP_HEIGHT = 26
local GROUP_ICON_SIZE = 14
local GROUP_COUNT_WIDTH = 16  -- the right-hand text (a count, up to 2 digits): narrow, so the title has the room
local GROUP_GAP = 4           -- between the icon, the title and the count
local GROUP_ATLAS = "glues-characterselect-icon-%s%s"  -- "plus" / "minus", "" / "-hover" / "-pressed"
local GROUP_ICON_COLLAPSED = "Interface\\Buttons\\UI-PlusButton-Up"
local GROUP_ICON_EXPANDED = "Interface\\Buttons\\UI-MinusButton-Up"
local hasGroupAtlas  -- checked on first use
local MUTED_ALPHA = 0.35     -- a card with `muted = true` (read-only items)
-- A section's tabs (`tabs`): one split button, a part per tab side by side (UIDef.UISplitButton:
-- the tab button cut straight where parts meet), the selected part gold, the others blank like an
-- unselected tab.
local TAB_HEIGHT = NEW_BUTTON_HEIGHT  -- as tall as the buttons under it
-- A section's search box (`search`), under its tabs, above its buttons.
local SEARCH_HEIGHT = NEW_BUTTON_HEIGHT  -- as tall as the buttons around it
local CARD_WIDTH = UIKit.Define.Percentage{ value = 100, operator = "-", delta = NAV_INDENT }

local SettingFrame = _G[Setting_Preload.FRAME_NAME]



-- Card (tab button look: gold when selected)

local CardMixin = CreateFromMixins(UICSharedMixin.ButtonMixin)

function CardMixin:OnLoad()
    self:InitButton()
    self.isSelected = false
    self.isGroup = false
    self.isMuted = false
    self.itemId = nil
    self.Group:Hide()

    self:RegisterMouseEvents()
    self:HookButtonStateChange(self.UpdateAnimation)
    self:HookClick(self.OnCardClick)
    self:HookMouseEnter(self.ShowFullText)
    self:HookMouseLeave(function(card) if GameTooltip:GetOwner() == card then GameTooltip:Hide() end end)
    self:UpdateAnimation()
end

--- Hovered: when any of the card's text is cut off ("..."), a tooltip shows all of it.
function CardMixin:ShowFullText()
    if self.isGroup then return end
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
    if self.isGroup then
        if self.onToggle then self.onToggle(self.itemId, self.isExpanded) end
        return
    end
    if self.onSelect then self.onSelect(self.itemId) end
end

function CardMixin:SetSelected(selected)
    self.isSelected = selected
    self:UpdateAnimation()
end

--- Shows the row as a group header (+/- toggle, title, count on the right) or as a card.
function CardMixin:SetGroup(isGroup, expanded)
    self.isGroup = isGroup
    self.isExpanded = isGroup and expanded or nil
    self.Info:SetShown(not isGroup)
    self.Group:SetShown(isGroup)
    self:size(CARD_WIDTH, isGroup and GROUP_HEIGHT or CARD_HEIGHT)
    self:UpdateAnimation()
end

--- The group row's +/- icon, following the row's state (hovered, pressed).
function CardMixin:UpdateGroupIcon(state)
    if hasGroupAtlas == nil then
        hasGroupAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GROUP_ATLAS:format("plus", "")) ~= nil or false
    end
    if hasGroupAtlas then
        local suffix = (state == "PUSHED" and "-pressed") or (state == "HIGHLIGHTED" and "-hover") or ""
        self.GroupIconTexture:SetAtlas(GROUP_ATLAS:format(self.isExpanded and "minus" or "plus", suffix))
    else
        self.GroupIconTexture:SetTexture(self.isExpanded and GROUP_ICON_EXPANDED or GROUP_ICON_COLLAPSED)
    end
end

--- Read-only items: the card's text dimmed (it stays selectable).
function CardMixin:SetMuted(muted)
    self.isMuted = muted and true or false
    self:UpdateAnimation()
end

function CardMixin:UpdateAnimation()
    local state = self:GetButtonState()
    local UIDef = Setting_Preload.UIDef
    if self.isGroup then
        -- A header, not a tab: no background, a highlight while hovered.
        self.Background:background(state ~= "NORMAL" and UIDef.UITabButton_Highlighted or UIKit.UI.TEXTURE_NIL)
        local alpha = state ~= "NORMAL" and 1 or 0.75
        self.Group:SetAlpha(self.isMuted and math.min(alpha, MUTED_ALPHA + 0.15) or alpha)
        self:UpdateGroupIcon(state)
        return
    end
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
    local alpha = (self.isSelected or state ~= "NORMAL") and 1 or 0.6
    self.Info:SetAlpha(self.isMuted and math.min(alpha, MUTED_ALPHA) or alpha)
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
                :frameLevel(2),

            -- Group header look (SetGroup): +/- toggle, title, count. Hidden on cards.
            Frame(name .. ".Group", {
                Frame(name .. ".Group.Icon")
                    :id("GroupIcon", id)
                    :point(UIKit.Enum.Point.Left)
                    :size(GROUP_ICON_SIZE, GROUP_ICON_SIZE),

                Text(name .. ".Group.Title")
                    :id("GroupTitle", id)
                    :fontObject(UIFont.UIFontObjectNormal12)
                    :textColor(HEADER_TEXT_COLOR)
                    :textAlignment("LEFT", "MIDDLE")
                    :point(UIKit.Enum.Point.Left)
                    :x(GROUP_ICON_SIZE + GROUP_GAP)
                    :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = GROUP_ICON_SIZE + GROUP_GAP + GROUP_COUNT_WIDTH + GROUP_GAP }, 14),

                Text(name .. ".Group.Count")
                    :id("GroupCount", id)
                    :fontObject(UIFont.UIFontObjectNormal11)
                    :textColor(HEADER_TEXT_COLOR)
                    :textAlignment("RIGHT", "MIDDLE")
                    :point(UIKit.Enum.Point.Right)
                    :size(GROUP_COUNT_WIDTH, 12)
            })
                :id("Group", id)
                :point(UIKit.Enum.Point.Left)
                :x(8)
                :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = 16 }, GROUP_HEIGHT)
                :frameLevel(2)
        })
        :size(CARD_WIDTH, CARD_HEIGHT)

    frame.Background = UIKit.GetElementById("Background", id)
    frame.Info = UIKit.GetElementById("Info", id)
    frame.Title = UIKit.GetElementById("Title", id)
    frame.Left = UIKit.GetElementById("Left", id)
    frame.Right = UIKit.GetElementById("Right", id)
    frame.Group = UIKit.GetElementById("Group", id)
    frame.GroupIcon = UIKit.GetElementById("GroupIcon", id)
    -- A plain texture: the icon is a game atlas (SetAtlas), which UIKit backgrounds don't take.
    frame.GroupIconTexture = frame.GroupIcon:CreateTexture(nil, "ARTWORK")
    frame.GroupIconTexture:SetAllPoints()
    frame.GroupTitle = UIKit.GetElementById("GroupTitle", id)
    frame.GroupCount = UIKit.GetElementById("GroupCount", id)

    Mixin(frame, CardMixin)
    frame:OnLoad()

    return frame
end)



-- Tab toggle (one part of a section's `tabs` split button, gold when selected)

local TabToggleMixin = CreateFromMixins(UICSharedMixin.ButtonMixin)

function TabToggleMixin:OnLoad()
    self:InitButton()
    self.isSelected = false
    self.tabId = nil
    self.part = "Left"

    self:RegisterMouseEvents()
    self:HookButtonStateChange(self.UpdateAnimation)
    self:HookClick(self.OnToggleClick)
    self:UpdateAnimation()
end

function TabToggleMixin:OnToggleClick()
    Sound.PlaySound("UI", SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if self.onSelect then self.onSelect(self.tabId) end
end

function TabToggleMixin:SetSelected(selected)
    self.isSelected = selected
    self:UpdateAnimation()
end

--- Where the part sits in the split button: "Left" and "Right" have the button's rounded ends,
--- "Middle" (between two others) is straight on both sides.
function TabToggleMixin:SetPart(part)
    self.part = part
    self:UpdateAnimation()
end

function TabToggleMixin:UpdateAnimation()
    local state = self:GetButtonState()
    local art = Setting_Preload.UIDef.UISplitButton[self.part]
    local texture
    if self.isSelected then
        texture = (state == "PUSHED" and art.Selected_Pushed)
            or (state == "HIGHLIGHTED" and art.Selected_Highlighted)
            or art.Selected
    else
        texture = (state == "PUSHED" and art.Pushed)
            or (state == "HIGHLIGHTED" and art.Highlighted)
            or art.Normal
    end
    self.Background:background(texture)
    self.Text:SetAlpha((self.isSelected or state ~= "NORMAL") and 1 or 0.6)
end

local TabToggle = UIKit.Template(function(id, name, children, ...)
    local frame =
        Frame(name, {
            Frame(name .. ".Background")
                :id("Background", id)
                :size(UIKit.UI.FILL)
                :background(UIKit.UI.TEXTURE_NIL)
                :_excludeFromCalculations(),

            Text(name .. ".Text")
                :id("Text", id)
                :fontObject(UIFont.UIFontObjectNormal12)
                :textAlignment("CENTER", "MIDDLE")
                :point(UIKit.Enum.Point.Center)
                :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = 12 }, 14)
        })

    frame.Background = UIKit.GetElementById("Background", id)
    frame.Text = UIKit.GetElementById("Text", id)

    Mixin(frame, TabToggleMixin)
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
        if section.tabs and #section.tabs > 0 then
            -- One split button: the toggles side by side, touching. Its art has no margin, so it
            -- fills the row like the buttons under it.
            local toggles = {}
            local count = #section.tabs
            for toggleIndex in ipairs(section.tabs) do
                toggles[toggleIndex] = TabToggle(name .. ".Tab" .. index .. "_" .. toggleIndex)
                    :id(key .. "Tab" .. toggleIndex, id)
                    :size(UIKit.Define.Percentage{ value = 100 / count }, TAB_HEIGHT)
            end
            tinsert(elements, Frame(name .. ".Tabs" .. index, {
                LayoutHorizontal(name .. ".Tabs" .. index .. ".Row", toggles)
                    :point(UIKit.Enum.Point.Center)
                    :size(UIKit.UI.P_FILL, TAB_HEIGHT)
                    :layoutSpacing(0)
            })
                :id(key .. "Tabs", id)
                :point(UIKit.Enum.Point.TopRight)
                :y(y)
                :size(CARD_WIDTH, TAB_HEIGHT))
            y = y - TAB_HEIGHT - NEW_BUTTON_GAP
        end
        if section.search then
            tinsert(elements, UICCommon.Input(name .. ".Search" .. index)
                :id(key .. "Search", id)
                :point(UIKit.Enum.Point.TopRight)
                :y(y)
                :size(CARD_WIDTH, SEARCH_HEIGHT))
            y = y - SEARCH_HEIGHT - NEW_BUTTON_GAP
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
            tabs = {},
            search = section.search and UIKit.GetElementById(key .. "Search", id) or nil,
            query = "",
            scroll = UIKit.GetElementById(key .. "Scroll", id),
            cards = UIKit.GetElementById(key .. "Cards", id),
            pool = {}
        }
        for actionIndex in ipairs(section.actions or {}) do
            refs.actions[actionIndex] = UIKit.GetElementById(key .. "Action" .. actionIndex, id)
        end
        if section.tabs and #section.tabs > 0 then
            local count = #section.tabs
            for toggleIndex in ipairs(section.tabs) do
                local toggle = UIKit.GetElementById(key .. "Tab" .. toggleIndex, id)
                toggle.Text:SetFrameLevel(toggle.Background:GetFrameLevel() + 1)  -- text over the art
                toggle:SetPart((toggleIndex == 1 and "Left") or (toggleIndex == count and "Right") or "Middle")
                refs.tabs[toggleIndex] = toggle
            end
        end
        AutoHideScrollBar(UIKit.GetElementById(key .. "ScrollBar", id), refs.scroll, refs.cards)
        frame.sections[index] = refs
    end
    return frame
end)

local NavMixin = {}

local function Contains(text, query)
    return string.find(string.lower(text or ""), query, 1, true) ~= nil
end

--- The keyword of `item` that contains `query`, or nil. `keywords`: a list, or a function returning
--- one (asked only while searching).
local function MatchKeyword(item, query)
    local keywords = item.keywords
    if type(keywords) == "function" then keywords = keywords() end
    for _, keyword in ipairs(type(keywords) == "table" and keywords or {}) do
        if Contains(keyword, query) then return keyword end
    end
end

--- The items whose title or a keyword contains `query` (lower case, plain text), each kept under
--- the group row it was under; groups without a match are left out. An item found by a keyword is
--- a copy with `match` = that keyword (its card shows it in place of the left detail).
local function FilterItems(items, query)
    local filtered, group = {}, nil
    for _, item in ipairs(items) do
        if item.group then
            group = item
        else
            local found = Contains(item.title, query) and item or nil
            if not found then
                local keyword = MatchKeyword(item, query)
                if keyword then
                    found = setmetatable({ match = keyword }, { __index = item })
                end
            end
            if found then
                if group then
                    filtered[#filtered + 1] = group
                    group = nil
                end
                filtered[#filtered + 1] = found
            end
        end
    end
    return filtered
end

function NavMixin:GetCard(sectionIndex, index)
    local refs = self.sections[sectionIndex]
    local card = refs.pool[index]
    if not card then
        card = Card(self.cardPrefix .. sectionIndex .. "_" .. index)
        card:parent(refs.cards)
        card.onSelect = function(itemId) self:Select(itemId) end
        card.onToggle = function(groupId, expanded) self:SetGroupCollapsed(groupId, expanded) end
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
        local refs = self.sections[sectionIndex]
        local current = section.getTab and section.getTab()
        for toggleIndex, tabSpec in ipairs(section.tabs or {}) do
            refs.tabs[toggleIndex]:SetSelected(tabSpec.id == current)
        end

        -- Group rows head the items after them; a collapsed group's items aren't shown. While
        -- searching: only matching items, under their groups (shown open), in any group.
        local items = section.getItems() or {}
        local searching = refs.query ~= ""
        if searching then items = FilterItems(items, refs.query) end
        local rows, hiding, y = 0, false, 0
        refs.positions = {}  -- [itemId] = { top, bottom } in the list, for ScrollTo
        for _, item in ipairs(items) do
            if item.group or not hiding then
                local height = item.group and GROUP_HEIGHT or CARD_HEIGHT
                refs.positions[item.id] = { y, y + height }
                y = y + height + CARD_SPACING
                rows = rows + 1
                local card = self:GetCard(sectionIndex, rows)
                card.itemId = item.id
                if item.group then
                    hiding = not searching and self:IsGroupCollapsed(item)
                    card.GroupTitle:SetText(item.title or "")
                    card.GroupCount:SetText(item.right or "")
                    card:SetGroup(true, not hiding)
                    card:SetSelected(false)
                else
                    card.Title:SetText(item.title or "")
                    -- Found by a keyword while searching: that keyword, so it's clear why it's listed.
                    card.Left:SetText(item.match or item.left or "")
                    card.Right:SetText(item.right or "")
                    card:SetGroup(false)
                    card:SetSelected(tabOpen and item.id == selected)
                end
                card:SetMuted(item.muted)
                card:Show()
            end
        end
        for index = rows + 1, #refs.pool do
            refs.pool[index]:Hide()
        end
    end
    self:_Render()
end

--- Whether group row `item` is collapsed: as toggled (kept in spec.collapsed), else its own
--- `collapsed` (the default; expanded when left out).
function NavMixin:IsGroupCollapsed(item)
    local toggled = self.collapsed[item.id]
    if toggled == nil then return item.collapsed == true end
    return toggled
end

--- Collapses or expands group `groupId` (as clicking its row does), and refreshes (unless
--- `noRefresh`: the caller refreshes next, e.g. with Select).
function NavMixin:SetGroupCollapsed(groupId, collapsed, noRefresh)
    self.collapsed[groupId] = collapsed and true or false
    if self.spec.onGroupToggle then self.spec.onGroupToggle(groupId, self.collapsed[groupId]) end
    if not noRefresh then self:Refresh() end
end

--- Scrolls the list just enough to show `itemId`'s card (nothing if it's in view, or not listed:
--- in a collapsed group, or filtered out by the search). Next frame: the list's height has to
--- catch up with a refresh first, or the scroll stops short of new cards at the bottom.
function NavMixin:ScrollTo(itemId)
    C_Timer.After(0, function()
        for _, refs in ipairs(self.sections) do
            local position = refs.positions and refs.positions[itemId]
            if position then
                local top, bottom = position[1], position[2]
                local scroll = refs.scroll:GetVerticalScroll() or 0
                local height = refs.scroll:GetHeight()
                if top < scroll then
                    refs.scroll:SetVerticalScroll(top)
                elseif bottom > scroll + height then
                    refs.scroll:SetVerticalScroll(bottom - height)
                end
                return
            end
        end
    end)
end

--- Selects `itemId`: tells the addon, opens the tab if another one is showing, refreshes, and
--- scrolls its card into view.
function NavMixin:Select(itemId)
    if self.spec.onSelect then self.spec.onSelect(itemId) end
    if not self.tab:IsShown() then Setting:OpenTabByIndex(self.tabIndex) end
    self:Refresh()
    self:ScrollTo(itemId)
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
    -- Toggled groups: the addon's table when it passes one (to keep them between sessions).
    nav.collapsed = spec.collapsed or {}

    for index, section in ipairs(spec.sections) do
        local refs = nav.sections[index]
        if refs.header then refs.header:SetText(section.title or "") end
        if refs.newButton then
            refs.newButton:SetText(section.newButton.text or "")
            refs.newButton:HookClick(function() section.newButton.onClick() end)
        end
        if refs.search then
            refs.search:SetPlaceholder(section.search.placeholder or "")
            local input = refs.search:GetInput()
            input:HookEvent("OnTextChanged", function()
                refs.query = string.lower(strtrim(input:GetText() or ""))
                nav:Refresh()
            end)
            -- Escape clears the search first (then the frame's own Escape handling applies).
            input:HookEvent("OnEscapePressed", function()
                if input:GetText() ~= "" then input:SetText("") end
                input:ClearFocus()
            end)
        end
        for toggleIndex, tabSpec in ipairs(section.tabs or {}) do
            local toggle = refs.tabs[toggleIndex]
            toggle.Text:SetText(tabSpec.text or "")
            toggle.tabId = tabSpec.id
            toggle.onSelect = function(tabId)
                if section.onTab then section.onTab(tabId) end
                if not tab:IsShown() then Setting:OpenTabByIndex(tabIndex) end
                nav:Refresh()
            end
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
