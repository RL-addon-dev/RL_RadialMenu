--[[
    Rings_Tab: the Menus tab ("Rings" in code, a Setting_Enum.WidgetType.Custom). It has two parts.
        Sidebar     a list nav (AX_Settings' Setting.AttachListNav) with two tabs, "+ New" and
                    Import, a search box (filtering both tabs by menu name, keybind or action), and
                    one scrolling list of collapsible groups, kept closed or open between sessions.
                      My Menus   the user's menus by scope (Account, <Class>s, This Character),
                                 then the Library menus in use ("Library": bound ones, then ones
                                 used as submenus of bound menus), then other classes' and other
                                 characters' menus (read-only)
                      Library    every built-in menu, by category (Ring_Data.LibraryCategoryOrder),
                                 closed at first
                    Cards show the name, keybind and scope, and clicking one opens this tab on that
                    menu. Import shows its page (Share\Rings_Import.lua) in the menu's place
                    (page.isImporting).
        Page        one column (the content area is too narrow for two). The wheel preview (with
                    the Add Action panel under it while adding, and the quick action set on the
                    preview's center), then Menu Settings (Name, Keybind with its capture,
                    Available On), then Share Menu (Share\Rings_Share.lua, not for built-in menus),
                    Removed Actions (Rings_Removed.lua, for built-in menus with some removed), and
                    Delete.

    Everything edits Ring_Data. Both parts rebuild on env.Event.DataChanged while the settings are
    shown, and on Setting_Enum.Event.Refresh when they're shown again (OnSettingRefresh).

    The files (one module, Rings_Tab, with the page's methods in PageMixin, shared through
    "@\\Setting\\Rings\\Tab\\Private"):
        Tab.lua           this file, with the page, the preview and Add Action, and the wiring
        Nav.lua           the sidebar's menu list
        SettingRows.lua   the Menu Settings rows (name, keybind capture, scope) and Delete
]]

local env = select(2, ...)
local L = env.L
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Frame, _, _, LayoutVertical = unpack(UIKit.UI.Frames)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Setting_Widgets = env.AX_Modules:Import("@\\Setting\\Widgets")
local Setting = env.AX_Modules:Await("@\\Setting")
local Ring_Data = env.AX_Modules:Await("@\\Ring\\Data")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Rings_Preview = env.AX_Modules:Import("@\\Setting\\Rings\\Preview")
local Rings_AddSlice = env.AX_Modules:Import("@\\Setting\\Rings\\AddSlice")
local Rings_Keybind = env.AX_Modules:Import("@\\Setting\\Rings\\Keybind")
local Rings_Share = env.AX_Modules:Import("@\\Setting\\Rings\\Share")
local Rings_Removed = env.AX_Modules:Import("@\\Setting\\Rings\\Removed")
local Rings_Import = env.AX_Modules:Import("@\\Setting\\Rings\\Import")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Ring_Kinds = env.AX_Modules:Await("@\\Ring\\Kinds")
local Rings_Tab = env.AX_Modules:New("@\\Setting\\Rings\\Tab")
local Private = env.AX_Modules:New("@\\Setting\\Rings\\Tab\\Private")

local format = string.format

local SettingFrame = _G[Setting_Preload.FRAME_NAME]

--- Runs `fn` next frame, after the render pass in progress. UIKit drops renders queued during a
--- render pass, and a hidden box can't take focus, so a change made from inside one (the host
--- switching, the Import page growing, the list nav opening this tab) waits a frame.
---@param fn function
local function AfterRender(fn)
    C_Timer.After(0, fn)
end



-- Tab page

--- The Menus tab's page's methods (Rings_Tab.Build). Nav.lua and SettingRows.lua add some. The
--- page keeps:
---     selectedRingId    the menu shown
---     isAddingSlice     the Add Action panel is open
---     isImporting       the Import page shows instead of a menu
---     isUpdating        the rows are being filled, not edited (RefreshSettingRows)
---     capturingRingId   the menu whose keybind is being captured
---     navTab            the sidebar list's tab (a Private.NavTab value)
local PageMixin = {}
Private.PageMixin = PageMixin

--- The selected menu: one of this character's, or one that lives elsewhere (another class's or
--- character's, read-only, see GetSelectedElsewhere).
---@return Ring?
function PageMixin:GetSelectedRing()
    if not self.selectedRingId then return nil end
    return Ring_Data.GetRing(self.selectedRingId) or (Ring_Data.GetElsewhereRing(self.selectedRingId))
end

--- When the selected menu lives elsewhere, its owner (Ring_Data.GetElsewhereRing's class, keybind
--- there and character), else nil.
---@return table?
function PageMixin:GetSelectedElsewhere()
    if not self.selectedRingId then return nil end
    local _, owner = Ring_Data.GetElsewhereRing(self.selectedRingId)
    return owner
end

--- A card was clicked (the list nav then opens this tab). It leaves Import.
---@param ringId string
function PageMixin:SelectRing(ringId)
    if ringId ~= self.selectedRingId then
        self.isAddingSlice = false
        Rings_Keybind.CancelCapture()
    end
    self.isImporting = false
    self.selectedRingId = ringId
    self:Refresh()
end

--- The sidebar's Import button shows that page instead of a menu's, empty (each click starts a
--- new import).
function PageMixin:ShowImport()
    self.isAddingSlice = false
    Rings_Keybind.CancelCapture()
    self.isImporting = true
    self.ImportPanel:Clear()
    self:RefreshSettings()
    self.tab:_Render()
    -- The list nav opens this tab after this, and the page has its new height then. It scrolls to
    -- the top, so the paste box is in view.
    AfterRender(function()
        if not self.isImporting then return end
        self.tab.Content:ScrollToTop()
        self.ImportPanel:FocusPaste()
    end)
end

--- Opens the Add Action panel under the preview (pushing Menu Settings down). When it's already
--- open, it just moves where the next action goes, keeping the search.
---@param index integer? insert so the new action becomes #index (nil adds it at the end)
function PageMixin:ShowAddSlice(index)
    if self.isAddingSlice then
        self.AddSlice:SetInsertIndex(index)
        return
    end
    self.isAddingSlice = true
    self:RefreshSettings()
    self.AddSlice:Open(index)
    self.tab:_Render()
end

--- Closes the Add Action panel.
function PageMixin:ShowPreview()
    if not self.isAddingSlice then return end
    self.isAddingSlice = false
    self.AddSlice.SearchBox:GetInput():ClearFocus()
    self:RefreshSettings()
    self.tab:_Render()
end

--- Shows the parts of the page that apply to the selected menu (or the Import page), and fills
--- them.
function PageMixin:RefreshSettings()
    -- Import replaces the menu's page.
    self.ImportPanel:SetShown(self.isImporting)
    if self.isImporting then
        self.Preview:Hide()
        self.AddSlice:Hide()
        self.Settings:Hide()
        self.ShareBox:Hide()
        self.RemovedBox:Hide()
        self.DeleteBox:Hide()
        self.Empty:Hide()
        self.ImportPanel:Refresh()
        return
    end

    local ring = self:GetSelectedRing()
    -- A menu that lives elsewhere is shown, not edited: no Add Action, Delete or Removed Actions.
    local elsewhere = self:GetSelectedElsewhere()
    -- Built-in menus can't be added to by hand.
    if not ring or Ring_Data.IsBuiltIn(ring) or elsewhere then self.isAddingSlice = false end
    -- The Add Slice panel opens under the preview while adding.
    self.Preview:SetShown(ring ~= nil)
    self.AddSlice:SetShown(ring ~= nil and self.isAddingSlice)
    self.Settings:SetShown(ring ~= nil)
    self.ShareBox:SetShown(ring ~= nil and not Ring_Data.IsBuiltIn(ring))
    self.RemovedBox:SetRing(not elsewhere and ring or nil) -- shown while a built-in menu has removed actions
    self.DeleteBox:SetShown(ring ~= nil and not elsewhere)
    self.Empty:SetShown(ring == nil)
    self.preview:SetReadOnly(Ring_Data.IsBuiltIn(ring), ring and ring.builtin)
    self.preview:SetLocked(elsewhere ~= nil)
    self.preview:SetRing(ring)
    if not ring then return end

    if self.isAddingSlice then
        self.AddSlice:UpdateTitle()
        self.AddSlice:Update()
    end

    self:RefreshSettingRows(ring)
    if not Ring_Data.IsBuiltIn(ring) then self.ShareBox:SetRing(ring) end
end

--- Refreshes the list and the page.
function PageMixin:Refresh()
    self:RefreshNav()
    self:RefreshSettings()
    self.tab:_Render()
end

--- The settings were shown again, and the menus may have changed while they were hidden.
function PageMixin:OnSettingRefresh()
    if SettingFrame:IsVisible() then self:Refresh() end
end



-- Actions

--- Creates a menu (account-wide) and opens it.
function PageMixin:CreateNewRing()
    local ring = Ring_Data.CreateRing(L["Config - Rings - NewRing - DefaultName"], Ring_Data.Scope.Account)
    self:RevealInMyMenus(ring.id, true)
end



-- Preview edits

--- An edit's result: a click sound when it worked, the reason in chat when it didn't.
---@param ok boolean?
---@param err string?
---@return boolean?
local function Report(ok, err)
    if ok then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    elseif err then
        env.Print(format(L["Config - Rings - Search - AddFailed"], err))
    end
    return ok
end

--- What the preview's wheel does to the selected menu (see Rings_Preview.Create).
---@param page table
---@return table
local function PreviewCallbacks(page)
    -- fn(ring, ...) for the selected menu, or false without one.
    local function Edit(fn)
        return function(...)
            local ring = page:GetSelectedRing()
            if not ring then return false end
            return fn(ring, ...)
        end
    end

    return {
        onAdd = function(index) page:ShowAddSlice(index) end,
        onRemove = Edit(function(ring, index) Ring_Data.RemoveSlice(ring.id, index) end),
        onMove = Edit(function(ring, from, to) Ring_Data.MoveSlice(ring.id, from, to) end),
        onSwap = Edit(function(ring, a, b) Ring_Data.SwapSlices(ring.id, a, b) end),
        -- Dropped from the game: onto an action, between actions, onto the center (tap-only).
        onReplace = Edit(function(ring, index, slice) return Report(Ring_Data.ReplaceSlice(ring.id, index, slice)) end),
        onDrop = Edit(function(ring, slice, index) return Report(Ring_Data.AddSlice(ring.id, slice, index)) end),
        onSetQuick = Edit(function(ring, slice) return Report(Ring_Data.SetQuickSlice(ring.id, slice)) end),
        -- An action copied into the center, and the center's action dragged onto the wheel.
        onQuickFromSlice = Edit(function(ring, index)
            Report(Ring_Data.CopySliceToQuick(ring.id, index))
        end),
        onQuickToWheel = Edit(function(ring, index, replace)
            Report(Ring_Data.MoveQuickSliceToWheel(ring.id, index, replace))
        end),
        -- The center's X.
        onClearQuick = Edit(function(ring)
            local cleared = Ring_Data.GetQuickActionSlice(ring)
            if not cleared then return end
            env.Print(format(L["Config - Rings - QuickAction - Cleared"], Ring_Actions.GetLabel(cleared)))
            Ring_Data.ClearQuickAction(ring.id)
        end),
        -- A double-click on the center cycles empty (Close Menu), Last Used, First Action, then
        -- empty again. Another quick action is only cleared with the X, never by a double-click.
        onToggleQuick = Edit(function(ring)
            local quick = Ring_Data.GetQuickActionSlice(ring)
            if not quick then
                Report(Ring_Data.SetQuickSlice(ring.id, { kind = Ring_Kinds.Kind.LastUsed }))
            elseif quick.kind == Ring_Kinds.Kind.LastUsed then
                Report(Ring_Data.SetQuickSlice(ring.id, { kind = Ring_Kinds.Kind.First }))
            elseif quick.kind == Ring_Kinds.Kind.First then
                Report(Ring_Data.ClearQuickAction(ring.id))
            end
        end),
        -- A double-click on a submenu switches it between scroll and spread.
        onToggleExpand = Edit(function(ring, index)
            local slice = ring.slices[index]
            if slice then Report(Ring_Data.SetSliceExpand(ring.id, index, not slice.expand)) end
        end),
    }
end



-- Construction

local Page = UIKit.Template(function(id, name, children, ...)
    local frame =
        LayoutVertical(name, {
            -- Untitled, since the page only ever shows one menu (its name is in the sidebar).
            Setting_Widgets.Container(name .. ".Preview", {
                Frame(name .. ".PreviewHost")
                    :id("PreviewHost", id)
                    :size(UIKit.UI.P_FILL, Rings_Preview.HEIGHT)
            })
                :id("Preview", id),

            -- Shown under the preview while adding an action.
            Rings_AddSlice.Panel(name .. ".AddSlice")
                :id("AddSlice", id),

            Setting_Widgets.ContainerWithTitle(name .. ".Settings", {
                Setting_Widgets.ElementInput(name .. ".Name"):id("NameRow", id),
                Setting_Widgets.ElementButton(name .. ".Keybind"):id("KeybindRow", id),
                Setting_Widgets.ElementSelectionMenu(name .. ".Scope"):id("ScopeRow", id)
            })
                :id("Settings", id),

            -- This menu's share string (user menus).
            Rings_Share.Box(name .. ".ShareBox")
                :id("ShareBox", id),

            -- Actions removed from a built-in menu, to restore.
            Rings_Removed.Box(name .. ".RemovedBox")
                :id("RemovedBox", id),

            -- Delete in its own untitled box, apart from the settings.
            Setting_Widgets.Container(name .. ".DeleteBox", {
                Setting_Widgets.ElementButton(name .. ".Delete"):id("DeleteRow", id)
            })
                :id("DeleteBox", id),

            Setting_Widgets.ElementText(name .. ".Empty")
                :id("Empty", id),

            -- The sidebar's Import button shows this instead of a menu.
            Rings_Import.Panel(name .. ".Import")
                :id("ImportPanel", id)
        })
        :size(UIKit.UI.P_FILL, UIKit.Define.Fit{})
        :layoutSpacing(10)
        :_updateMode(UIKit.Enum.UpdateMode.ChildrenVisibilityChanged)

    frame.Preview = UIKit.GetElementById("Preview", id)
    frame.PreviewHost = UIKit.GetElementById("PreviewHost", id)
    frame.AddSlice = UIKit.GetElementById("AddSlice", id)
    frame.Settings = UIKit.GetElementById("Settings", id)
    frame.DeleteBox = UIKit.GetElementById("DeleteBox", id)
    frame.Empty = UIKit.GetElementById("Empty", id)
    frame.NameRow = UIKit.GetElementById("NameRow", id)
    frame.KeybindRow = UIKit.GetElementById("KeybindRow", id)
    frame.ScopeRow = UIKit.GetElementById("ScopeRow", id)
    frame.DeleteRow = UIKit.GetElementById("DeleteRow", id)
    frame.ShareBox = UIKit.GetElementById("ShareBox", id)
    frame.RemovedBox = UIKit.GetElementById("RemovedBox", id)
    frame.ImportPanel = UIKit.GetElementById("ImportPanel", id)

    Mixin(frame, PageMixin)

    return frame
end)

--- The Setting_Enum.WidgetType.Custom builder. It also attaches the menu list to the sidebar,
--- right under this tab's button (the Menus tab is the last non-footer tab).
---@param parent Frame
---@param tab table
---@return table page
function Rings_Tab.Build(parent, tab)
    local page = Page("RLRM_RingsPage")
    page:parent(parent)
    page.tab = tab

    page.Settings:SetSubcontainer(false) -- the container's background art, as Build.Container does
    page.Settings.Title:SetText(L["Config - Rings - Settings - Title"])
    page.DeleteBox:SetSubcontainer(false)
    page.Preview:SetTransparent(true) -- the wheel sits on the page background, with no box
    page.AddSlice:Setup(function() return page:GetSelectedRing() end, function() page:ShowPreview() end)
    -- Moving between Options and our window changes how many results fit, so an open Add Action
    -- panel renders again (after the render pass the host change happens in).
    CallbackRegistry.Add(Setting_Enum.Event.HostChanged, function()
        if not page.isAddingSlice then return end
        AfterRender(function()
            if page.AddSlice:UpdateResultsHeight() then page.tab:_Render() end
        end)
    end)
    page.AddSlice:ForwardMouseWheelWhenIdle(tab.Content)
    page.AddSlice:Hide()
    page.preview = Rings_Preview.Create(page.PreviewHost, PreviewCallbacks(page))
    page.Empty:SetInfo(L["Config - Rings - Empty"], nil)
    Private.SetupSettingRows(page)

    page.ShareBox:Setup()
    page.RemovedBox:Setup()
    -- The Import page's height changes as it fills, which can happen inside a render pass.
    local function RenderSoon() AfterRender(function() page.tab:_Render() end) end
    page.ImportPanel:Setup(RenderSoon, function(rings)
        if rings[1] then page.Nav:Select(rings[1].id) end
    end)
    page.ImportPanel:Hide()

    page.navTab = Private.NavTab.Mine
    page.Nav = Setting.AttachListNav(tab, {
        sections = {
            {
                title    = L["Config - Rings - Nav - Title"],
                tabs     = {
                    { id = Private.NavTab.Mine, text = L["Config - Rings - Nav - Mine"] },
                    { id = Private.NavTab.Library, text = L["Config - Rings - Nav - Library"] },
                },
                search   = { placeholder = L["Config - Rings - Nav - Search"] },
                getTab   = function() return page.navTab end,
                onTab    = function(tabId) page.navTab = tabId end,
                -- Side by side, since both make menus.
                actions  = {
                    { text = L["Config - Rings - NewRing"], onClick = function() page:CreateNewRing() end },
                    { text = L["Config - Rings - Nav - Import"], onClick = function() page:ShowImport() end },
                },
                getItems = function()
                    if page.navTab == Private.NavTab.Library then return page:GetLibraryItems() end
                    return page:GetMyMenusItems()
                end,
            },
        },
        collapsed   = Private.SavedCollapsedGroups(),
        -- No menu card lit while importing.
        getSelected = function() return not page.isImporting and page.selectedRingId or nil end,
        onSelect    = function(ringId) page:SelectRing(ringId) end,
    })

    tab:HookScript("OnHide", function()
        Rings_Keybind.CancelCapture()
        page:ShowPreview()
    end)

    -- Only while the settings are shown, because automatic refills (bags, quests) happen all the
    -- time, and reopening the settings refreshes anyway (OnSettingRefresh).
    CallbackRegistry.Add(env.Event.DataChanged, function()
        if SettingFrame:IsVisible() then page:Refresh() end
    end)
    -- The preview's center shows the last used action for a Last Used quick action.
    CallbackRegistry.Add(env.Event.LastUsedChanged, function()
        if SettingFrame:IsVisible() then page.preview:SetRing(page:GetSelectedRing()) end
    end)
    page:Refresh()

    return page
end
