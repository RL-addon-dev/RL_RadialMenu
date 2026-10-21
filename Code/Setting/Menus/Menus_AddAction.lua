--[[
    Menus_AddAction: the Add Action panel of the Menus tab, with a search box, a kind filter, Done,
    and the results. It opens under the preview, pushing the menu's settings down. The preview's
    "+" opens it, on a gap to insert there or on an empty menu, and another "+" while it's open
    just moves where the next action goes.

    The results come from Menu_Search. Clicking a row or its Add button (or Enter in the search
    box, for the top result) adds the action. The panel stays open for more, and its heading says
    where the next one goes and what was just added. A number also looks up a spell, item, toy
    or mount by id. Done, or Esc in the search box, closes it.
]]

local env = select(2, ...)
local L = env.L
local UIFont = env.AX_Modules:Import("ax_modules\\ui-font")
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Frame, LayoutGrid, LayoutHorizontal, LayoutVertical, Text, ScrollView = unpack(UIKit.UI.Frames)
local UICSharedMixin = env.AX_Modules:Import("ax_modules\\uic-sharedmixin")
local UICCommon = env.AX_Modules:Import("ax_modules\\uic-common")
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Setting_Widgets = env.AX_Modules:Import("@\\Setting\\Widgets")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Setting = env.AX_Modules:Await("@\\Setting")
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")
local Menu_Search = env.AX_Modules:Await("@\\Menu\\Search")
local Menu_Layout = env.AX_Modules:Await("@\\Menu\\Layout")
local Menu_Kinds = env.AX_Modules:Await("@\\Menu\\Kinds")
local Menus_AddAction = env.AX_Modules:New("@\\Setting\\Menus\\AddAction")

local SEARCH_HEIGHT = 32
local KIND_WIDTH = 120
local SEARCH_GAP = 8
local DONE_WIDTH = 70
local ROW_HEIGHT = 40
local ROW_SPACING = 3
local ROW_ICON_SIZE = 28
local ROW_ICON_X = 10 -- from the row's left edge
local ROW_TEXT_GAP = 18 -- the text starts this far past the icon's size, and stops this far before Add
local ROW_NAME_Y, ROW_KIND_Y = 7, -8 -- the two text lines, from the row's middle
local ROW_BACKGROUND_INSET = 6
local ADD_WIDTH = 64
local ADD_HEIGHT = 24
local ADD_X = -8 -- from the row's right edge
local HINT_HEIGHT = 60
local HINT_MARGIN = 40 -- the hint's width is the list's, minus this
local SCROLLBAR_GAP = 8
-- Result rows shown before the list scrolls: fewer in the Options panel (shorter), more in our
-- own window. See Setting.GetHost.
local VISIBLE_ROWS_OPTIONS = 3
local VISIBLE_ROWS_WINDOW = 4

--- The results list's height for `rows` rows.
---@param rows integer
---@return number
local function ResultsHeight(rows)
    return rows * (ROW_HEIGHT + ROW_SPACING)
end
local SCROLLBAR_WIDTH = 6
local RESULT_LIMIT = 40
local BLOCKED_ALPHA = 0.45
local KIND_SEPARATOR = "  ·  " -- between a result's kind and its note

local SettingFrame = _G[Setting_Preload.FRAME_NAME]



-- Result row

local ResultRowMixin = CreateFromMixins(UICSharedMixin.ButtonMixin)

--- Sets up the row as a button.
function ResultRowMixin:OnLoad()
    self:InitButton()
    self:RegisterMouseEvents()
    self:HookButtonStateChange(self.UpdateAnimation)
    self:HookMouseEnter(self.ShowTooltip)
    self:HookMouseLeave(function() GameTooltip:Hide() end)
    self:HookClick(function(row) row.panel:AddResult(row.result) end)
    self:UpdateAnimation()
end

--- Shows the row's background while hovered or pressed.
function ResultRowMixin:UpdateAnimation()
    self.Background:SetShown(self:GetButtonState() ~= "NORMAL")
end

--- Shows `result` on the row.
---@param result SearchCandidate
function ResultRowMixin:SetResult(result)
    self.result = result
    Menu_Layout.SetIcon(self.IconFrame.Icon, result.icon or Menu_Kinds.QUESTION_MARK_ICON)
    -- Like on the wheel, there's no action button border for kinds without one (markers, Close).
    self.IconFrame.Border:SetShown(not (result.action and Menu_Actions.HasNoIconBorder(result.action)))
    Menu_Layout.SetUnderlay(self.IconFrame, result.action) -- a world marker's beam, as on the wheel
    self.Name:SetText(result.name)

    -- "Config - Menus - Search - Kind - <kind>", one per action kind (Menu_Kinds.Kind).
    local kindText = result.kindLabel or L["Config - Menus - Search - Kind - " .. result.kind]
    -- Blocked results (a menu that would contain itself) stay visible but can't be added. A note
    -- only explains (a gear slot with no use effect).
    local extra = result.blocked or result.note
    self.Kind:SetText(extra and (kindText .. KIND_SEPARATOR .. extra) or kindText)
    self:SetAlpha(result.blocked and BLOCKED_ALPHA or 1)
    self.Add:SetEnabled(not result.blocked)
end

--- The result's tooltip, and how to add it.
function ResultRowMixin:ShowTooltip()
    local action = self.result and self.result.action
    if not action then return end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not Menu_Actions.SetTooltip(GameTooltip, action) then
        GameTooltip:SetText(self.result.name, 1, 1, 1)
    end
    GameTooltip:AddLine(L["Config - Menus - Search - ClickToAdd"], 0.5, 0.8, 1)
    GameTooltip:Show()
end

local ResultRow = UIKit.Template(function(id, name, children, ...)
    local textX = ROW_ICON_SIZE + ROW_TEXT_GAP
    local textWidth = UIKit.Define.Percentage{ value = 100, operator = "-", delta = textX + ADD_WIDTH + ROW_TEXT_GAP }

    local frame =
        Frame(name, {
            Frame(name .. ".Background")
                :id("Background", id)
                :size(UIKit.Define.Fill{ delta = -ROW_BACKGROUND_INSET })
                :background(Setting_Preload.UIDef.UIWidget)
                :frameLevel(1)
                :_excludeFromCalculations(),

            Text(name .. ".Name")
                :id("Name", id)
                :point(UIKit.Enum.Point.Left)
                :x(textX)
                :y(ROW_NAME_Y)
                :size(textWidth, 14)
                :fontObject(UIFont.UIFontObjectNormal12)
                :textAlignment("LEFT", "MIDDLE")
                :frameLevel(2),

            Text(name .. ".Kind")
                :id("Kind", id)
                :point(UIKit.Enum.Point.Left)
                :x(textX)
                :y(ROW_KIND_Y)
                :size(textWidth, 12)
                :fontObject(UIFont.UIFontObjectNormal11)
                :textAlignment("LEFT", "MIDDLE")
                :alpha(0.6)
                :frameLevel(2),

            UICCommon.ButtonRedWithText(name .. ".Add")
                :id("Add", id)
                :point(UIKit.Enum.Point.Right)
                :x(ADD_X)
                :size(ADD_WIDTH, ADD_HEIGHT)
                :frameLevel(3)
        })
        :size(UIKit.UI.P_FILL, ROW_HEIGHT)

    frame.Background = UIKit.GetElementById("Background", id)
    frame.Name = UIKit.GetElementById("Name", id)
    frame.Kind = UIKit.GetElementById("Kind", id)
    frame.Add = UIKit.GetElementById("Add", id)

    frame.IconFrame = Menu_Layout.CreateActionIcon(frame, ROW_ICON_SIZE)
    frame.IconFrame:SetPoint("LEFT", frame, "LEFT", ROW_ICON_X, 0)

    Mixin(frame, ResultRowMixin)
    frame:OnLoad()
    frame.Add:SetText(L["Config - Menus - Search - Add"])
    frame.Add:HookClick(function() frame.panel:AddResult(frame.result) end)

    return frame
end)



-- Panel

--- The panel's methods. It keeps the results, the kind filter (kindIndex), where the next action
--- goes (insertIndex, nil adds it at the end), and the last action added (lastAdded).
local AddActionMixin = {}

--- The kind filter's value (a Menu_Search.Kinds entry).
---@return string
function AddActionMixin:GetKind()
    return Menu_Search.Kinds[self.kindIndex or 1]
end

--- Result row `index`, made on first use.
---@param index integer
---@return table
function AddActionMixin:GetRow(index)
    local row = self.rows[index]
    if not row then
        row = ResultRow(self.rowNamePrefix .. index)
        row:parent(self.Rows)
        row.panel = self
        row:_Render()
        self.rows[index] = row
    end
    return row
end

--- Searches again, and shows the results (or a hint).
function AddActionMixin:Update()
    local menu = self.getMenu()
    if not menu then return end

    local query = self.SearchBox:GetInput():GetText() or ""
    local results, truncated = Menu_Search.Search(query, self:GetKind(), menu.id, RESULT_LIMIT)
    self.results = results

    for index, result in ipairs(results) do
        local row = self:GetRow(index)
        row:SetResult(result)
        row:Show()
    end
    for index = #results + 1, #self.rows do
        self.rows[index]:Hide()
    end

    local hint
    if #results == 0 then
        local waiting = strtrim(query) == "" and self:GetKind() == Menu_Search.ALL
        hint = (waiting and L["Config - Menus - Search - Hint"]) or L["Config - Menus - Search - NoMatches"]
    elseif truncated then
        hint = nil -- the list is full, and the user can refine the query
    end
    self.Hint:SetShown(hint ~= nil)
    if hint then self.Hint:SetText(hint) end

    self.Scroll:_Render()
end

--- Adds `result` to the menu, where the next action goes.
---@param result SearchCandidate?
function AddActionMixin:AddResult(result)
    local menu = self.getMenu()
    if not (menu and result) or result.blocked then return end

    local ok, err = Menu_Data.AddAction(menu.id, CopyTable(result.action), self.insertIndex)
    if ok then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        -- Also confirm in the heading what was added (the wheel above shows it too).
        self.lastAdded = result.name
        -- Keep adding after the one just inserted, so several adds stay in order.
        if self.insertIndex then self.insertIndex = self.insertIndex + 1 end
        self:UpdateTitle()
    else
        env.Print(format(L["Config - Menus - Search - AddFailed"], err or "?"))
    end
end

--- Starts a search session.
---@param index integer? insert so the new action becomes #index (nil adds it at the end)
function AddActionMixin:Open(index)
    self:UpdateResultsHeight() -- the caller re-renders the page after opening
    self.insertIndex = index
    self.lastAdded = nil

    -- Every session starts fresh: an empty search, the All filter, and the list at the top.
    local input = self.SearchBox:GetInput()
    input:SetText("")
    self.kindIndex = 1
    self.KindMenu:SetValue(1)
    self.Scroll:ScrollToTop(true)

    self:UpdateTitle()
    self:Update()
    input:SetFocus()
end

--- Moves where the next action goes while open (another "+" on the preview), keeping the search.
---@param index integer?
function AddActionMixin:SetInsertIndex(index)
    self.insertIndex = index
    self.lastAdded = nil
    self:UpdateTitle()
    self.SearchBox:GetInput():SetFocus()
end

--- The heading: where the next action goes, and what was just added.
function AddActionMixin:UpdateTitle()
    local menu = self.getMenu()
    local atEnd = not self.insertIndex or not menu or self.insertIndex > #menu.actions
    local where = atEnd and L["Config - Menus - Search - AtEnd"] or format(L["Config - Menus - Search - AtIndex"], self.insertIndex)
    if self.lastAdded then
        where = format(L["Config - Menus - Search - Added"], where, self.lastAdded)
    end
    self.Title:SetText(where)
end

--- The results list only takes the mouse wheel when it has something to scroll. Otherwise the
--- wheel scrolls the page.
---@param outerScrollView table the tab's scroll view
function AddActionMixin:ForwardMouseWheelWhenIdle(outerScrollView)
    local scrollFrame = self.Scroll:GetScrollFrame()
    local ownHandler = scrollFrame:GetScript("OnMouseWheel")
    local outerFrame = outerScrollView:GetScrollFrame()

    scrollFrame:SetScript("OnMouseWheel", function(frame, delta)
        local overflows = (self.Scroll:GetContentHeight() or 0) > frame:GetHeight() + 1
        if overflows then
            ownHandler(frame, delta)
        else
            local outerHandler = outerFrame:GetScript("OnMouseWheel")
            if outerHandler then outerHandler(outerFrame, delta) end
        end
    end)
end

--- Sizes the results list for where the settings are shown.
---@return boolean changed the page needs rendering again
function AddActionMixin:UpdateResultsHeight()
    local rows = Setting.GetHost() == Setting_Enum.Host.Window and VISIBLE_ROWS_WINDOW or VISIBLE_ROWS_OPTIONS
    if rows == self.visibleRows then return false end
    self.visibleRows = rows
    self.Results:size(UIKit.UI.P_FILL, ResultsHeight(rows))
    return true
end

--- Sets up the panel's texts and handlers.
---@param getMenu fun(): Menu? the menu being edited
---@param onDone function called by the Done button, or Esc in the search box
function AddActionMixin:Setup(getMenu, onDone)
    self.getMenu = getMenu
    self.rows = {}
    self.kindIndex = 1

    self:SetSubcontainer(false)
    self:UpdateTitle()

    self.SearchBox.Input:fontSize(13)
    self.SearchBox:SetPlaceholder(L["Config - Menus - Search - Placeholder"])
    local input = self.SearchBox:GetInput()
    input:HookEvent("OnTextChanged", function() self:Update() end)
    input:HookScript("OnEnterPressed", function()
        if self.results and self.results[1] then self:AddResult(self.results[1]) end
    end)
    input:HookEvent("OnEscapePressed", function() onDone() end)

    local labels = {}
    -- "Config - Menus - Search - Filter - <kind>", one per Menu_Search.Kinds entry.
    for index, kind in ipairs(Menu_Search.Kinds) do
        labels[index] = L["Config - Menus - Search - Filter - " .. kind]
    end
    self.KindMenu:SetSelectionMenu(SettingFrame.SelectionMenu)
    self.KindMenu:SetData(labels)
    self.KindMenu:HookValueChanged(function(_, index)
        if index == self.kindIndex then return end
        self.kindIndex = index
        self:Update()
    end)

    self.DoneButton:SetText(L["Config - Menus - Search - Done"])
    self.DoneButton:HookClick(function() onDone() end)

    CallbackRegistry.Add(env.Event.SearchSourcesChanged, function()
        if self:IsVisible() then self:Update() end
    end)
    -- When the settings close, it lets go of the last results too, with the search lists (Menu_Search).
    CallbackRegistry.Add(Setting_Enum.Event.HostChanged, function(_, host)
        if not host then self.results = nil end
    end)
end

Menus_AddAction.Panel = UIKit.Template(function(id, name, children, ...)
    local frame =
        Setting_Widgets.ContainerWithTitle(name, {
            Frame(name .. ".SearchRow", {
                UICCommon.Input(name .. ".Search")
                    :id("Search", id)
                    :point(UIKit.Enum.Point.Left)
                    :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = KIND_WIDTH + DONE_WIDTH + SEARCH_GAP * 2 }, SEARCH_HEIGHT),

                UICCommon.ButtonSelectionMenu(name .. ".Kind")
                    :id("Kind", id)
                    :point(UIKit.Enum.Point.Right)
                    :x(-(DONE_WIDTH + SEARCH_GAP))
                    :size(KIND_WIDTH, SEARCH_HEIGHT),

                UICCommon.ButtonRedWithText(name .. ".Done")
                    :id("Done", id)
                    :point(UIKit.Enum.Point.Right)
                    :size(DONE_WIDTH, SEARCH_HEIGHT)
            })
                :size(UIKit.UI.P_FILL, SEARCH_HEIGHT),

            -- UpdateResultsHeight sets the height (the rows depend on where the settings are shown).
            Frame(name .. ".Results", {
                ScrollView(name .. ".Scroll", {
                    LayoutVertical(name .. ".Rows")
                        :id("Rows", id)
                        :point(UIKit.Enum.Point.Top)
                        :size(UIKit.UI.P_FILL, UIKit.Define.Fit{})
                        :layoutSpacing(ROW_SPACING)
                        :_updateMode(UIKit.Enum.UpdateMode.ChildrenVisibilityChanged)
                })
                    :id("Scroll", id)
                    :point(UIKit.Enum.Point.TopLeft)
                    :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = SCROLLBAR_WIDTH + SCROLLBAR_GAP },
                        UIKit.UI.P_FILL)
                    :scrollViewContentWidth(UIKit.UI.P_FILL)
                    :scrollViewContentHeight(UIKit.Define.Fit{})
                    :layoutDirection(UIKit.Enum.Direction.Vertical)
                    :scrollInterpolation(10),

                UICCommon.ScrollBar(name .. ".ScrollBar")
                    :id("ScrollBar", id)
                    :point(UIKit.Enum.Point.TopRight)
                    :size(SCROLLBAR_WIDTH, UIKit.UI.P_FILL)
                    :linkedScrollView(UIKit.NewGroupCaptureString("Scroll", id)),

                Text(name .. ".Hint")
                    :id("Hint", id)
                    :point(UIKit.Enum.Point.Center)
                    :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = HINT_MARGIN }, HINT_HEIGHT)
                    :fontObject(UIFont.UIFontObjectNormal12)
                    :textAlignment("CENTER", "MIDDLE")
                    :alpha(0.6)
            })
                :id("Results", id)
                :size(UIKit.UI.P_FILL, ResultsHeight(VISIBLE_ROWS_OPTIONS))
        })

    frame.SearchBox = UIKit.GetElementById("Search", id)
    frame.KindMenu = UIKit.GetElementById("Kind", id)
    frame.DoneButton = UIKit.GetElementById("Done", id)
    frame.Results = UIKit.GetElementById("Results", id)
    frame.Scroll = UIKit.GetElementById("Scroll", id)
    frame.Rows = UIKit.GetElementById("Rows", id)
    frame.Hint = UIKit.GetElementById("Hint", id)

    Mixin(frame, AddActionMixin)
    frame.rowNamePrefix = name .. ".Row"

    return frame
end)
