--[[
    Menus_Tab: the Menus tab ("Menus" in code, a Setting_Enum.WidgetType.Custom). It has two parts.
        Sidebar     a list nav (AX_Settings' Setting.AttachListNav) with two tabs, "+ New" and
                    Import, a search box (filtering both tabs by menu name, keybind or action), and
                    one scrolling list of collapsible groups, kept closed or open between sessions.
                      My Menus   the user's menus by scope (Account, <Class>s, This Character),
                                 then the Library menus in use ("Library": bound ones, then ones
                                 used as submenus of bound menus), then other classes' and other
                                 characters' menus (read-only)
                      Library    every library menu, by category (Menu_Data.LibraryCategoryOrder),
                                 closed at first
                    Cards show the name, keybind and scope, and clicking one opens this tab on that
                    menu. Import shows its page (Share\Menus_Import.lua) in the menu's place
                    (page.isImporting).
        Page        one column (the content area is too narrow for two). The wheel preview (with
                    the Add Action panel under it while adding, and the quick action set on the
                    preview's center), then Menu Settings (Name, Keybind with its capture,
                    Available On), then Share Menu (Share\Menus_Share.lua, not for library menus),
                    Removed Actions (Menus_Removed.lua, for library menus with some removed), and
                    Delete.

    Everything edits Menu_Data. Both parts rebuild on env.Event.DataChanged while the settings are
    shown, and on Setting_Enum.Event.Refresh when they're shown again (OnSettingRefresh).

    The files (one module, Menus_Tab, with the page's methods in PageMixin, shared through
    "@\\Setting\\Menus\\Tab\\Private"):
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
local Menu_Data = env.AX_Modules:Await("@\\Menu\\Data")
local Menu_Actions = env.AX_Modules:Await("@\\Menu\\Actions")
local Menus_Preview = env.AX_Modules:Import("@\\Setting\\Menus\\Preview")
local Menus_AddAction = env.AX_Modules:Import("@\\Setting\\Menus\\AddAction")
local Menus_Keybind = env.AX_Modules:Import("@\\Setting\\Menus\\Keybind")
local Menus_Share = env.AX_Modules:Import("@\\Setting\\Menus\\Share")
local Menus_Removed = env.AX_Modules:Import("@\\Setting\\Menus\\Removed")
local Menus_Import = env.AX_Modules:Import("@\\Setting\\Menus\\Import")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Menu_Kinds = env.AX_Modules:Await("@\\Menu\\Kinds")
local Menus_Tab = env.AX_Modules:New("@\\Setting\\Menus\\Tab")
local Private = env.AX_Modules:New("@\\Setting\\Menus\\Tab\\Private")

local format = string.format

local SettingFrame = _G[Setting_Preload.FRAME_NAME]



-- Tab page

--- The Menus tab's page's methods (Menus_Tab.Build). Nav.lua and SettingRows.lua add some. The
--- page keeps:
---     selectedMenuId    the menu shown
---     isAddingAction    the Add Action panel is open
---     isImporting       the Import page shows instead of a menu
---     isUpdating        the rows are being filled, not edited (RefreshSettingRows)
---     capturingMenuId   the menu whose keybind is being captured
---     navTab            the sidebar list's tab (a Private.NavTab value)
local PageMixin = {}
Private.PageMixin = PageMixin

--- The selected menu: one of this character's, or one that lives elsewhere (another class's or
--- character's, read-only, see GetSelectedElsewhere).
---@return Menu?
function PageMixin:GetSelectedMenu()
    if not self.selectedMenuId then return nil end
    return Menu_Data.GetMenu(self.selectedMenuId) or (Menu_Data.GetElsewhereMenu(self.selectedMenuId))
end

--- When the selected menu lives elsewhere, its owner (Menu_Data.GetElsewhereMenu's class, keybind
--- there and character), else nil.
---@return table?
function PageMixin:GetSelectedElsewhere()
    if not self.selectedMenuId then return nil end
    local _, owner = Menu_Data.GetElsewhereMenu(self.selectedMenuId)
    return owner
end

--- A card was clicked (the list nav then opens this tab). It leaves Import.
---@param menuId string
function PageMixin:SelectMenu(menuId)
    if menuId ~= self.selectedMenuId then
        self.isAddingAction = false
        Menus_Keybind.CancelCapture()
    end
    self.isImporting = false
    self.selectedMenuId = menuId
    self:Refresh()
end

--- The sidebar's Import button shows that page instead of a menu's, empty (each click starts a
--- new import).
function PageMixin:ShowImport()
    self.isAddingAction = false
    Menus_Keybind.CancelCapture()
    self.isImporting = true
    self.ImportPanel:Clear()
    self:RefreshSettings()
    self.tab:_Render()
    -- Next frame, because the list nav opens this tab after this, and a hidden box can't take
    -- focus. The page has its new height then too. It scrolls to the top, so the paste box is in
    -- view.
    C_Timer.After(0, function()
        if not self.isImporting then return end
        self.tab.Content:ScrollToTop()
        self.ImportPanel:FocusPaste()
    end)
end

--- Opens the Add Action panel under the preview (pushing Menu Settings down). When it's already
--- open, it just moves where the next action goes, keeping the search.
---@param index integer? insert so the new action becomes #index (nil adds it at the end)
function PageMixin:ShowAddAction(index)
    if self.isAddingAction then
        self.AddAction:SetInsertIndex(index)
        return
    end
    self.isAddingAction = true
    self:RefreshSettings()
    self.AddAction:Open(index)
    self.tab:_Render()
end

--- Closes the Add Action panel.
function PageMixin:ShowPreview()
    if not self.isAddingAction then return end
    self.isAddingAction = false
    self.AddAction.SearchBox:GetInput():ClearFocus()
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
        self.AddAction:Hide()
        self.Settings:Hide()
        self.ShareBox:Hide()
        self.RemovedBox:Hide()
        self.DeleteBox:Hide()
        self.Empty:Hide()
        self.ImportPanel:Refresh()
        return
    end

    local menu = self:GetSelectedMenu()
    -- A menu that lives elsewhere is shown, not edited: no Add Action, Delete or Removed Actions.
    local elsewhere = self:GetSelectedElsewhere()
    -- Library menus can't be added to by hand.
    if not menu or Menu_Data.IsLibraryMenu(menu) or elsewhere then self.isAddingAction = false end
    -- The Add Action panel opens under the preview while adding.
    self.Preview:SetShown(menu ~= nil)
    self.AddAction:SetShown(menu ~= nil and self.isAddingAction)
    self.Settings:SetShown(menu ~= nil)
    self.ShareBox:SetShown(menu ~= nil and not Menu_Data.IsLibraryMenu(menu))
    self.RemovedBox:SetMenu(not elsewhere and menu or nil) -- shown while a library menu has removed actions
    self.DeleteBox:SetShown(menu ~= nil and not elsewhere)
    self.Empty:SetShown(menu == nil)
    self.preview:SetReadOnly(Menu_Data.IsLibraryMenu(menu), menu and menu.library)
    self.preview:SetLocked(elsewhere ~= nil)
    self.preview:SetMenu(menu)
    if not menu then return end

    if self.isAddingAction then
        self.AddAction:UpdateTitle()
        self.AddAction:Update()
    end

    self:RefreshSettingRows(menu)
    if not Menu_Data.IsLibraryMenu(menu) then self.ShareBox:SetMenu(menu) end
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
function PageMixin:CreateNewMenu()
    local menu = Menu_Data.CreateMenu(L["Config - Menus - NewMenu - DefaultName"], Menu_Data.Scope.Account)
    self:RevealInMyMenus(menu.id, true)
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
        env.Print(format(L["Config - Menus - Search - AddFailed"], err))
    end
    return ok
end

--- What the preview's wheel does to the selected menu (see Menus_Preview.Create).
---@param page table
---@return table
local function PreviewCallbacks(page)
    -- fn(menu, ...) for the selected menu, or false without one.
    local function Edit(fn)
        return function(...)
            local menu = page:GetSelectedMenu()
            if not menu then return false end
            return fn(menu, ...)
        end
    end

    return {
        onAdd = function(index) page:ShowAddAction(index) end,
        onRemove = Edit(function(menu, index) Menu_Data.RemoveAction(menu.id, index) end),
        onMove = Edit(function(menu, from, to) Menu_Data.MoveAction(menu.id, from, to) end),
        onSwap = Edit(function(menu, a, b) Menu_Data.SwapActions(menu.id, a, b) end),
        -- Dropped from the game: onto an action, between actions, onto the center (tap-only).
        onReplace = Edit(function(menu, index, action) return Report(Menu_Data.ReplaceAction(menu.id, index, action)) end),
        onDrop = Edit(function(menu, action, index) return Report(Menu_Data.AddAction(menu.id, action, index)) end),
        onSetQuick = Edit(function(menu, action) return Report(Menu_Data.SetQuickAction(menu.id, action)) end),
        -- An action copied into the center, and the center's action dragged onto the wheel.
        onQuickFromAction = Edit(function(menu, index)
            Report(Menu_Data.CopyActionToQuick(menu.id, index))
        end),
        onQuickToWheel = Edit(function(menu, index, replace)
            Report(Menu_Data.MoveQuickActionToWheel(menu.id, index, replace))
        end),
        -- The center's X.
        onClearQuick = Edit(function(menu)
            local cleared = Menu_Data.GetQuickAction(menu)
            if not cleared then return end
            env.Print(format(L["Config - Menus - QuickAction - Cleared"], Menu_Actions.GetLabel(cleared)))
            Menu_Data.ClearQuickAction(menu.id)
        end),
        -- A double-click on the center cycles empty (Close Menu), Last Used, First Action, then
        -- empty again. Another quick action is only cleared with the X, never by a double-click.
        onToggleQuick = Edit(function(menu)
            local quick = Menu_Data.GetQuickAction(menu)
            if not quick then
                Report(Menu_Data.SetQuickAction(menu.id, { kind = Menu_Kinds.Kind.LastUsed }))
            elseif quick.kind == Menu_Kinds.Kind.LastUsed then
                Report(Menu_Data.SetQuickAction(menu.id, { kind = Menu_Kinds.Kind.First }))
            elseif quick.kind == Menu_Kinds.Kind.First then
                Report(Menu_Data.ClearQuickAction(menu.id))
            end
        end),
        -- A double-click on a submenu switches it between scroll and spread.
        onToggleSpread = Edit(function(menu, index)
            local action = menu.actions[index]
            if action then Report(Menu_Data.SetSubmenuSpread(menu.id, index, not action.spread)) end
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
                    :size(UIKit.UI.P_FILL, Menus_Preview.HEIGHT)
            })
                :id("Preview", id),

            -- Shown under the preview while adding an action.
            Menus_AddAction.Panel(name .. ".AddAction")
                :id("AddAction", id),

            Setting_Widgets.ContainerWithTitle(name .. ".Settings", {
                Setting_Widgets.ElementInput(name .. ".Name"):id("NameRow", id),
                Setting_Widgets.ElementButton(name .. ".Keybind"):id("KeybindRow", id),
                Setting_Widgets.ElementSelectionMenu(name .. ".Scope"):id("ScopeRow", id)
            })
                :id("Settings", id),

            -- This menu's share string (user menus).
            Menus_Share.Box(name .. ".ShareBox")
                :id("ShareBox", id),

            -- Actions removed from a library menu, to restore.
            Menus_Removed.Box(name .. ".RemovedBox")
                :id("RemovedBox", id),

            -- Delete in its own untitled box, apart from the settings.
            Setting_Widgets.Container(name .. ".DeleteBox", {
                Setting_Widgets.ElementButton(name .. ".Delete"):id("DeleteRow", id)
            })
                :id("DeleteBox", id),

            Setting_Widgets.ElementText(name .. ".Empty")
                :id("Empty", id),

            -- The sidebar's Import button shows this instead of a menu.
            Menus_Import.Panel(name .. ".Import")
                :id("ImportPanel", id)
        })
        :size(UIKit.UI.P_FILL, UIKit.Define.Fit{})
        :layoutSpacing(10)
        :_updateMode(UIKit.Enum.UpdateMode.ChildrenVisibilityChanged)

    frame.Preview = UIKit.GetElementById("Preview", id)
    frame.PreviewHost = UIKit.GetElementById("PreviewHost", id)
    frame.AddAction = UIKit.GetElementById("AddAction", id)
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
function Menus_Tab.Build(parent, tab)
    local page = Page("RLRM_MenusPage")
    page:parent(parent)
    page.tab = tab

    page.Settings:SetSubcontainer(false) -- the container's background art, as Build.Container does
    page.Settings.Title:SetText(L["Config - Menus - Settings - Title"])
    page.DeleteBox:SetSubcontainer(false)
    page.Preview:SetTransparent(true) -- the wheel sits on the page background, with no box
    page.AddAction:Setup(function() return page:GetSelectedMenu() end, function() page:ShowPreview() end)
    -- Moving between Options and our window changes how many results fit, so an open Add Action
    -- panel renders again. UIKit gives a render asked for during a render pass its own pass.
    CallbackRegistry.Add(Setting_Enum.Event.HostChanged, function()
        if page.isAddingAction and page.AddAction:UpdateResultsHeight() then page.tab:_Render() end
    end)
    page.AddAction:ForwardMouseWheelWhenIdle(tab.Content)
    page.AddAction:Hide()
    page.preview = Menus_Preview.Create(page.PreviewHost, PreviewCallbacks(page))
    page.Empty:SetInfo(L["Config - Menus - Empty"], nil)
    Private.SetupSettingRows(page)

    page.ShareBox:Setup()
    page.RemovedBox:Setup()
    -- The Import page's height changes as it fills (inside a render pass is fine, see above).
    page.ImportPanel:Setup(function() page.tab:_Render() end, function(menus)
        if menus[1] then page.Nav:Select(menus[1].id) end
    end)
    page.ImportPanel:Hide()

    page.navTab = Private.NavTab.Mine
    page.Nav = Setting.AttachListNav(tab, {
        sections = {
            {
                title    = L["Config - Menus - Nav - Title"],
                tabs     = {
                    { id = Private.NavTab.Mine, text = L["Config - Menus - Nav - Mine"] },
                    { id = Private.NavTab.Library, text = L["Config - Menus - Nav - Library"] },
                },
                search   = { placeholder = L["Config - Menus - Nav - Search"] },
                getTab   = function() return page.navTab end,
                onTab    = function(tabId) page.navTab = tabId end,
                -- Side by side, since both make menus.
                actions  = {
                    { text = L["Config - Menus - NewMenu"], onClick = function() page:CreateNewMenu() end },
                    { text = L["Config - Menus - Nav - Import"], onClick = function() page:ShowImport() end },
                },
                getItems = function()
                    if page.navTab == Private.NavTab.Library then return page:GetLibraryItems() end
                    return page:GetMyMenusItems()
                end,
            },
        },
        collapsed   = Private.SavedCollapsedGroups(),
        -- No menu card lit while importing.
        getSelected = function() return not page.isImporting and page.selectedMenuId or nil end,
        onSelect    = function(menuId) page:SelectMenu(menuId) end,
    })

    tab:HookScript("OnHide", function()
        Menus_Keybind.CancelCapture()
        page:ShowPreview()
    end)

    -- Only while the settings are shown, because automatic refills (bags, quests) happen all the
    -- time, and reopening the settings refreshes anyway (OnSettingRefresh).
    CallbackRegistry.Add(env.Event.DataChanged, function()
        if SettingFrame:IsVisible() then page:Refresh() end
    end)
    -- The preview's center shows the last used action for a Last Used quick action.
    CallbackRegistry.Add(env.Event.LastUsedChanged, function()
        if SettingFrame:IsVisible() then page.preview:SetMenu(page:GetSelectedMenu()) end
    end)
    page:Refresh()

    return page
end
