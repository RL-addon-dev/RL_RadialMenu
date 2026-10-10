--[[
    "Add Action" panel (AddSlice in code) for the Menus tab: search box + kind dropdown + Done +
    results. It opens under the preview, pushing the menu's settings down (opened by the preview's
    "+": on a gap to insert there, or on an empty menu; another "+" while open just moves where
    the next action goes).

    Results come from Ring_Search. Clicking a row or its Add button (or Enter in the search box
    for the top result) adds the slice; the panel stays open for more, and its heading says where
    the next one goes and what was just added. A number also looks up a spell / item / toy /
    mount by id. Done or Esc in the search box closes it.
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
local Setting = env.AX_Modules:Await("@\\Setting")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Ring_Search = env.AX_Modules:Await("@\\Ring\\Search")
local Ring_Layout = env.AX_Modules:Await("@\\Ring\\Layout")
local Rings_AddSlice = env.AX_Modules:New("@\\Setting\\Rings\\AddSlice")

local SEARCH_HEIGHT = 32
local KIND_WIDTH = 120
local SEARCH_GAP = 8
local DONE_WIDTH = 70
local ROW_HEIGHT = 40
local ROW_SPACING = 3
local ROW_ICON_SIZE = 28
local ADD_WIDTH = 64
local ADD_HEIGHT = 24
-- Result rows shown before the list scrolls: fewer in the Options panel (shorter), more in our
-- own window. See Setting.GetHost.
local VISIBLE_ROWS_OPTIONS = 3
local VISIBLE_ROWS_WINDOW = 4

local function ResultsHeight(rows)
    return rows * (ROW_HEIGHT + ROW_SPACING)
end
local SCROLLBAR_WIDTH = 6
local RESULT_LIMIT = 40
local BLOCKED_ALPHA = 0.45

local SettingFrame = _G[Setting_Preload.FRAME_NAME]



-- Result row

local ResultRowMixin = CreateFromMixins(UICSharedMixin.ButtonMixin)

function ResultRowMixin:OnLoad()
    self:InitButton()
    self:RegisterMouseEvents()
    self:HookButtonStateChange(self.UpdateAnimation)
    self:HookMouseEnter(self.ShowTooltip)
    self:HookMouseLeave(function() GameTooltip:Hide() end)
    self:HookClick(function(row) row.panel:AddResult(row.result) end)
    self:UpdateAnimation()
end

function ResultRowMixin:UpdateAnimation()
    self.Background:SetShown(self:GetButtonState() ~= "NORMAL")
end

function ResultRowMixin:SetResult(result)
    self.result = result
    Ring_Layout.SetIcon(self.IconFrame.Icon, result.icon or 134400)
    -- Like on the wheel: no action button border for kinds without one (markers, Close).
    self.IconFrame.Border:SetShown(not (result.slice and Ring_Actions.HasNoIconBorder(result.slice)))
    self.Name:SetText(result.name)

    -- Blocked results (e.g. a ring that would nest in a loop) stay visible but can't be added.
    local kindText = result.kindLabel or L["Config - Rings - Search - Kind - " .. result.kind]
    -- Blocked results can't be added; a note only explains (e.g. a gear slot with no use effect).
    local extra = result.blocked or result.note
    self.Kind:SetText(extra and (kindText .. "  ·  " .. extra) or kindText)
    self:SetAlpha(result.blocked and BLOCKED_ALPHA or 1)
    self.Add:SetEnabled(not result.blocked)
end

function ResultRowMixin:ShowTooltip()
    local slice = self.result and self.result.slice
    if not slice then return end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not Ring_Actions.SetTooltip(GameTooltip, slice) then
        GameTooltip:SetText(self.result.name, 1, 1, 1)
    end
    GameTooltip:AddLine(L["Config - Rings - Search - ClickToAdd"], 0.5, 0.8, 1)
    GameTooltip:Show()
end

local ResultRow = UIKit.Template(function(id, name, children, ...)
    local textX = ROW_ICON_SIZE + 18
    local textWidth = UIKit.Define.Percentage{ value = 100, operator = "-", delta = textX + ADD_WIDTH + 18 }

    local frame =
        Frame(name, {
            Frame(name .. ".Background")
                :id("Background", id)
                :size(UIKit.Define.Fill{ delta = -6 })
                :background(Setting_Preload.UIDef.UIWidget)
                :frameLevel(1)
                :_excludeFromCalculations(),

            Text(name .. ".Name")
                :id("Name", id)
                :point(UIKit.Enum.Point.Left)
                :x(textX)
                :y(7)
                :size(textWidth, 14)
                :fontObject(UIFont.UIFontObjectNormal12)
                :textAlignment("LEFT", "MIDDLE")
                :frameLevel(2),

            Text(name .. ".Kind")
                :id("Kind", id)
                :point(UIKit.Enum.Point.Left)
                :x(textX)
                :y(-8)
                :size(textWidth, 12)
                :fontObject(UIFont.UIFontObjectNormal11)
                :textAlignment("LEFT", "MIDDLE")
                :alpha(0.6)
                :frameLevel(2),

            UICCommon.ButtonRedWithText(name .. ".Add")
                :id("Add", id)
                :point(UIKit.Enum.Point.Right)
                :x(-8)
                :size(ADD_WIDTH, ADD_HEIGHT)
                :frameLevel(3)
        })
        :size(UIKit.UI.P_FILL, ROW_HEIGHT)

    frame.Background = UIKit.GetElementById("Background", id)
    frame.Name = UIKit.GetElementById("Name", id)
    frame.Kind = UIKit.GetElementById("Kind", id)
    frame.Add = UIKit.GetElementById("Add", id)

    frame.IconFrame = Ring_Layout.CreateActionIcon(frame, ROW_ICON_SIZE)
    frame.IconFrame:SetPoint("LEFT", frame, "LEFT", 10, 0)

    Mixin(frame, ResultRowMixin)
    frame:OnLoad()
    frame.Add:SetText(L["Config - Rings - Search - Add"])
    frame.Add:HookClick(function() frame.panel:AddResult(frame.result) end)

    return frame
end)



-- Panel

local AddSliceMixin = {}

function AddSliceMixin:GetKind()
    return Ring_Search.Kinds[self.kindIndex or 1]
end

function AddSliceMixin:GetRow(index)
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

function AddSliceMixin:Update()
    local ring = self.getRing()
    if not ring then return end

    local query = self.SearchBox:GetInput():GetText() or ""
    local results, truncated = Ring_Search.Search(query, self:GetKind(), ring.id, RESULT_LIMIT)
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
        hint = (strtrim(query) == "" and self:GetKind() == "all") and L["Config - Rings - Search - Hint"] or L["Config - Rings - Search - NoMatches"]
    elseif truncated then
        hint = nil -- the list is full; the user can refine the query
    end
    self.Hint:SetShown(hint ~= nil)
    if hint then self.Hint:SetText(hint) end

    self.Scroll:_Render()
end

function AddSliceMixin:AddResult(result)
    local ring = self.getRing()
    if not (ring and result) or result.blocked then return end

    local ok, err = Ring_Data.AddSlice(ring.id, CopyTable(result.slice), self.insertIndex)
    if ok then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        -- Also confirm in the heading what was added (the wheel above shows it too).
        self.lastAdded = result.name
        -- Keep adding after the one just inserted, so several adds stay in order.
        if self.insertIndex then self.insertIndex = self.insertIndex + 1 end
        self:UpdateTitle()
    else
        env.Print(format(L["Config - Rings - Search - AddFailed"], err or "?"))
    end
end

--- Starts a search session.
--- @param index number|nil insert so the new slice becomes #index (nil = add at the end)
function AddSliceMixin:Open(index)
    self:UpdateResultsHeight() -- the caller re-renders the page after opening
    self.insertIndex = index
    self.lastAdded = nil

    -- Every session starts fresh: empty search, "All" filter, list scrolled to the top.
    local input = self.SearchBox:GetInput()
    input:SetText("")
    self.kindIndex = 1
    self.KindMenu:SetValue(1)
    self.Scroll:ScrollToTop(true)

    self:UpdateTitle()
    self:Update()
    input:SetFocus()
end

--- While open: move where the next slice goes (another "+" on the preview), keeping the search.
function AddSliceMixin:SetInsertIndex(index)
    self.insertIndex = index
    self.lastAdded = nil
    self:UpdateTitle()
    self.SearchBox:GetInput():SetFocus()
end

function AddSliceMixin:UpdateTitle()
    local ring = self.getRing()
    local atEnd = not self.insertIndex or not ring or self.insertIndex > #ring.slices
    local where = atEnd and L["Config - Rings - Search - AtEnd"] or format(L["Config - Rings - Search - AtIndex"], self.insertIndex)
    if self.lastAdded then
        where = format(L["Config - Rings - Search - Added"], where, self.lastAdded)
    end
    self.Title:SetText(where)
end

--- The results list only takes the mouse wheel when it has something to scroll; otherwise the
--- wheel scrolls the page (`outerScrollView`, the tab's scroll view).
function AddSliceMixin:ForwardMouseWheelWhenIdle(outerScrollView)
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

--- Sizes the results list for where the settings are shown. Returns true if it changed (the page
--- needs a re-render).
function AddSliceMixin:UpdateResultsHeight()
    local rows = Setting.GetHost() == "window" and VISIBLE_ROWS_WINDOW or VISIBLE_ROWS_OPTIONS
    if rows == self.visibleRows then return false end
    self.visibleRows = rows
    self.Results:size(UIKit.UI.P_FILL, ResultsHeight(rows))
    return true
end

--- @param getRing function returns the ring being edited
--- @param onDone function called by the Done button / Esc in the search box
function AddSliceMixin:Setup(getRing, onDone)
    self.getRing = getRing
    self.rows = {}
    self.kindIndex = 1

    self:SetSubcontainer(false)
    self:UpdateTitle()

    self.SearchBox.Input:fontSize(13)
    self.SearchBox:SetPlaceholder(L["Config - Rings - Search - Placeholder"])
    local input = self.SearchBox:GetInput()
    input:HookEvent("OnTextChanged", function() self:Update() end)
    input:HookScript("OnEnterPressed", function()
        if self.results and self.results[1] then self:AddResult(self.results[1]) end
    end)
    input:HookEvent("OnEscapePressed", function() onDone() end)

    local labels = {}
    for index, kind in ipairs(Ring_Search.Kinds) do
        labels[index] = L["Config - Rings - Search - Filter - " .. kind]
    end
    self.KindMenu:SetSelectionMenu(SettingFrame.SelectionMenu)
    self.KindMenu:SetData(labels)
    self.KindMenu:HookValueChanged(function(_, index)
        if index == self.kindIndex then return end
        self.kindIndex = index
        self:Update()
    end)

    self.DoneButton:SetText(L["Config - Rings - Search - Done"])
    self.DoneButton:HookClick(function() onDone() end)

    CallbackRegistry.Add("Ring.SearchSourcesChanged", function()
        if self:IsVisible() then self:Update() end
    end)
end

Rings_AddSlice.Panel = UIKit.Template(function(id, name, children, ...)
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

            -- Height set by UpdateResultsHeight (rows depend on where the settings are shown).
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
                    :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = SCROLLBAR_WIDTH + 8 }, UIKit.UI.P_FILL)
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
                    :size(UIKit.Define.Percentage{ value = 100, operator = "-", delta = 40 }, 60)
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

    Mixin(frame, AddSliceMixin)
    frame.rowNamePrefix = name .. ".Row"

    return frame
end)
