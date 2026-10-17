--[[
    Menus tab ("Rings" in code; Setting_Enum.WidgetType.Custom).

    Two parts:
        Sidebar       a list nav (AX_Settings Setting.AttachListNav) with two tabs, "+ New" and
                      Import, a search box (filters both tabs by menu name, keybind or action), and one
                      scrolling list of collapsible groups (kept closed / open between sessions):
                        My Menus   the user's menus by scope (Account, <Class>s, This Character),
                                   then the Library menus in use ("Library": bound ones, then ones
                                   used as submenus of bound menus), then other classes' and other
                                   characters' menus (read-only)
                        Library    every built-in menu, by category (Ring_Data.LibraryCategoryOrder),
                                   closed at first
                      Cards show name, keybind and scope; clicking one opens this tab on that ring.
                      Import shows its page (Share\Rings_Import.lua) in the ring's place
                      (page.isImporting).
        Tab page      single column (the content area is too narrow for two): the wheel preview
                      (with the Add Action panel under it while adding; the quick action is set on
                      the preview's center), then Menu Settings: Name, Keybind (capture),
                      Available On, then Share Menu (Share\Rings_Share.lua; not for built-in
                      menus), Removed Actions (Rings_Removed.lua; built-in menus, when some are
                      removed), and Delete

    Everything edits Ring_Data; both parts rebuild on env.Event.DataChanged while the settings are
    shown (and on Setting_Enum.Event.Refresh when they're shown again, see OnSettingRefresh).

    Files (one module, Rings_Tab; the page's methods in PageMixin, shared through
    "@\\Setting\\Rings\\Tab\\Private"):
        Tab.lua           this file: the page, sidebar list, preview + Add Action, wiring
        SettingRows.lua   the Ring Settings rows (name, keybind capture, scope) and Delete
]]

local env = select(2, ...)
local L = env.L
local Config = env.Config
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
local Rings_Tab = env.AX_Modules:New("@\\Setting\\Rings\\Tab")
local Private = env.AX_Modules:New("@\\Setting\\Rings\\Tab\\Private")

local format = string.format

-- The sidebar list's tabs.
local NAV_MINE, NAV_LIBRARY = "mine", "library"

local SettingFrame = _G[Setting_Preload.FRAME_NAME]



-- Tab page

--- Methods of the page; SettingRows.lua adds the settings rows' ones.
local PageMixin = {}
Private.PageMixin = PageMixin

--- The selected menu: one of this character's, or one that lives elsewhere (another class's or
--- character's: read-only, see GetSelectedElsewhere).
function PageMixin:GetSelectedRing()
    if not self.selectedRingId then return nil end
    return Ring_Data.GetRing(self.selectedRingId) or (Ring_Data.GetElsewhereRing(self.selectedRingId))
end

--- When the selected menu lives elsewhere: its owner (Ring_Data.GetElsewhereRing: class, keybind
--- there, character), else nil.
function PageMixin:GetSelectedElsewhere()
    if not self.selectedRingId then return nil end
    local _, owner = Ring_Data.GetElsewhereRing(self.selectedRingId)
    return owner
end

--- A card was clicked (the list nav then opens this tab). Leaves Import.
function PageMixin:SelectRing(ringId)
    if ringId ~= self.selectedRingId then
        self.isAddingSlice = false
        Rings_Keybind.CancelCapture()
    end
    self.isImporting = false
    self.selectedRingId = ringId
    self:Refresh()
end

--- The sidebar's Import button: that page instead of a menu's, empty (each click starts a new
--- import).
function PageMixin:ShowImport()
    self.isAddingSlice = false
    Rings_Keybind.CancelCapture()
    self.isImporting = true
    self.ImportPanel:Clear()
    self:RefreshSettings()
    self.tab:_Render()
    -- Next frame: the list nav opens this tab after this (a hidden box can't take focus), and
    -- the page has its new height. From the top, so the paste box is in view.
    C_Timer.After(0, function()
        if not self.isImporting then return end
        self.tab.Content:ScrollToTop()
        self.ImportPanel:FocusPaste()
    end)
end

-- A menu card's scope label.
local CARD_SCOPE = {
    account   = "Config - Rings - Card - Account",
    class     = "Config - Rings - Card - Class",
    character = "Config - Rings - Card - Character",
}

--- The card's detail line: its keybind, and its scope (Library for built-in menus).
local function FormatRingMeta(ring)
    local _, scope = Ring_Data.GetRing(ring.id)
    local key = Ring_Data.GetBinding(ring.id)
    local keyText = key and Rings_Keybind.GetDisplayText(key) or L["Config - Rings - Card - NoKey"]
    local scopeText = Ring_Data.IsBuiltIn(ring) and L["Config - Rings - Card - Library"] or L[CARD_SCOPE[scope] or CARD_SCOPE.account]
    return keyText, scopeText
end

--- What the list's search box finds a menu by, besides its name: its keybind (as its card shows
--- it), then its action names (its wedges and its center), so a key or a spell finds every menu
--- it's on. Asked only while searching.
--- @param key string|nil its keybind ("CTRL-1"), nil when unbound
local function SearchKeywords(ring, key)
    return function()
        local names = { key and Rings_Keybind.GetDisplayText(key) or nil }
        for _, slice in ipairs(type(ring.slices) == "table" and ring.slices or {}) do
            names[#names + 1] = Ring_Actions.GetLabel(slice)
        end
        local quick = Ring_Data.GetQuickActionSlice(ring)
        if quick then names[#names + 1] = Ring_Actions.GetLabel(quick) end
        return names
    end
end

--- Adds a group row and its rings' cards (nothing for an empty group).
local function AddGroup(items, id, title, rings, collapsed)
    if #rings == 0 then return end
    items[#items + 1] = { group = true, id = id, title = title, right = tostring(#rings), collapsed = collapsed }
    for _, ring in ipairs(rings) do
        local keyText, scopeText = FormatRingMeta(ring)
        items[#items + 1] = { id = ring.id, title = ring.name, left = keyText, right = scopeText,
                              keywords = SearchKeywords(ring, Ring_Data.GetBinding(ring.id)) }
    end
end

local function ClassName(class)
    return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end

--- A read-only group (menus that live elsewhere: dimmed, opening one shows it locked), closed at
--- first. `entries`: { { ring, key, owner = the card's right text } }.
local function AddElsewhereGroup(items, id, title, entries)
    if #entries == 0 then return end
    items[#items + 1] = { group = true, id = id, title = title, right = tostring(#entries), collapsed = true, muted = true }
    for _, entry in ipairs(entries) do
        items[#items + 1] = {
            id = entry.ring.id, title = entry.ring.name, muted = true, right = entry.owner, keywords = SearchKeywords(entry.ring, entry.key),
            left = entry.key and Rings_Keybind.GetDisplayText(entry.key) or L["Config - Rings - Card - NoKey"],
        }
    end
end

--- Other classes' class menus, then other characters' menus (as of their last session).
local function AddElsewhere(items)
    local classes = {}
    for _, other in ipairs(Ring_Data.GetOtherClassRings()) do
        local _, _, key = Ring_Data.GetOtherClassRing(other.ring.id)
        classes[#classes + 1] = { ring = other.ring, key = key, owner = ClassName(other.class) }
    end
    AddElsewhereGroup(items, "other:classes", L["Config - Rings - Nav - OtherClasses"], classes)

    local characters = {}
    for _, other in ipairs(Ring_Data.GetOtherCharacterRings()) do
        characters[#characters + 1] = { ring = other.ring, key = other.key, owner = other.character.name }
    end
    AddElsewhereGroup(items, "other:characters", L["Config - Rings - Nav - OtherCharacters"], characters)
end

--- My Menus: the user's menus by scope, then the Library menus in use (one group: bound first,
--- then those used as submenus of bound menus, Ring_Data.GetOpenableRings), then other classes'
--- and characters' menus (read-only).
function PageMixin:GetMyMenusItems()
    local byScope, bound, inSubmenus = {}, {}, {}
    for _, scope in ipairs(Ring_Data.ScopeOrder) do byScope[scope] = {} end
    local _, openable = Ring_Data.GetOpenableRings()
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if not Ring_Data.IsBuiltIn(ring) then
            local _, scope = Ring_Data.GetRing(ring.id)
            table.insert(byScope[scope], ring)
        elseif Ring_Data.GetBinding(ring.id) then
            table.insert(bound, ring)
        elseif openable[ring.id] then
            table.insert(inSubmenus, ring)
        end
    end
    local items = {}
    for _, scope in ipairs(Ring_Data.ScopeOrder) do
        AddGroup(items, "scope:" .. scope, Ring_Data.GetScopeName(scope), byScope[scope])
    end
    for _, ring in ipairs(inSubmenus) do table.insert(bound, ring) end
    AddGroup(items, "library:inuse", L["Config - Rings - Nav - Library"], bound)
    AddElsewhere(items)
    return items
end

--- Library: every built-in menu by category, each group closed until opened.
function PageMixin:GetLibraryItems()
    local byCategory = {}
    for _, category in ipairs(Ring_Data.LibraryCategoryOrder) do byCategory[category] = {} end
    for _, ring in ipairs(Ring_Data.GetRings()) do
        if Ring_Data.IsBuiltIn(ring) then
            table.insert(byCategory[Ring_Data.GetLibraryCategory(ring)], ring)
        end
    end
    local items = {}
    for _, category in ipairs(Ring_Data.LibraryCategoryOrder) do
        AddGroup(items, "category:" .. category, L["Config - Rings - Library - " .. category], byCategory[category], true)
    end
    return items
end

local function FirstRingId(items)
    for _, item in ipairs(items) do
        if not item.group then return item.id end
    end
end

function PageMixin:RefreshNav()
    -- Keep a ring selected: the first of My Menus, else the first in the Library.
    if not self:GetSelectedRing() then
        self.selectedRingId = FirstRingId(self:GetMyMenusItems()) or FirstRingId(self:GetLibraryItems())
    end
    self.Nav:Refresh()
end

--- Which groups the user closed or opened ([groupId] = true / false), kept account-wide. Looked
--- up on each use: the settings can be built before the saved variables are loaded.
local function SavedCollapsedGroups()
    local function Stored(create)
        local db = Config.DBGlobalPersistent:GetData()
        if not db then return nil end
        if create and type(db.MenuListCollapsed) ~= "table" then db.MenuListCollapsed = {} end
        return type(db.MenuListCollapsed) == "table" and db.MenuListCollapsed or nil
    end
    return setmetatable({}, {
        __index = function(_, groupId)
            local stored = Stored(false)
            return stored and stored[groupId]
        end,
        __newindex = function(_, groupId, collapsed)
            local stored = Stored(true)
            if stored then stored[groupId] = collapsed end
        end,
    })
end

--- Opens the Add Slice panel under the preview (pushing Ring Settings down). Already open: just
--- moves where the next slice goes, keeping the search.
--- @param index number|nil insert so the new slice becomes #index (nil = add at the end)
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

function PageMixin:ShowPreview()
    if not self.isAddingSlice then return end
    self.isAddingSlice = false
    self.AddSlice.SearchBox:GetInput():ClearFocus()
    self:RefreshSettings()
    self.tab:_Render()
end

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
    -- Automatic rings can't be added to by hand.
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

function PageMixin:Refresh()
    self:RefreshNav()
    self:RefreshSettings()
    self.tab:_Render()
end

function PageMixin:OnSettingRefresh()
    -- Settings panel re-shown: ring data may have changed while it was hidden.
    if SettingFrame:IsVisible() then self:Refresh() end
end



-- Actions

--- Shows one of the user's menus in the sidebar: the My Menus tab, its scope's group opened, the
--- list scrolled to it. `select`: also select it (one refresh for both).
function PageMixin:RevealInMyMenus(ringId, select)
    local _, scope = Ring_Data.GetRing(ringId)
    if not scope then return end
    self.navTab = NAV_MINE
    self.Nav:SetGroupCollapsed("scope:" .. scope, false, true)
    if select then
        self.Nav:Select(ringId) -- refreshes and scrolls to it
    else
        self.Nav:Refresh()
        self.Nav:ScrollTo(ringId)
    end
end

function PageMixin:CreateNewRing()
    local ring = Ring_Data.CreateRing(L["Config - Rings - NewRing - DefaultName"], Ring_Data.Scope.Account)
    self:RevealInMyMenus(ring.id, true)
end



-- Preview edits

--- An edit's result: a click sound when it worked, the reason in chat when it didn't.
local function Report(ok, err)
    if ok then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    elseif err then
        env.Print(format(L["Config - Rings - Search - AddFailed"], err))
    end
    return ok
end

--- What the preview's wheel does to the selected menu (see Rings_Preview.Create).
local function PreviewCallbacks(page)
    -- fn(ring, ...) for the selected menu; false without one.
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
        -- Dropped from the game: onto a slice, between slices, onto the center (tap-only).
        onReplace = Edit(function(ring, index, slice) return Report(Ring_Data.ReplaceSlice(ring.id, index, slice)) end),
        onDrop = Edit(function(ring, slice, index) return Report(Ring_Data.AddSlice(ring.id, slice, index)) end),
        onSetQuick = Edit(function(ring, slice) return Report(Ring_Data.SetQuickSlice(ring.id, slice)) end),
        -- A wheel slice copied into the center, and the center's action dragged onto the wheel.
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
        -- Double-click on the center: empty (Close Menu) -> Last Used -> First Action -> empty.
        -- Another quick action is only cleared with the X, never by a double-click.
        onToggleQuick = Edit(function(ring)
            local quick = Ring_Data.GetQuickActionSlice(ring)
            if not quick then
                Report(Ring_Data.SetQuickSlice(ring.id, { kind = "lastused" }))
            elseif quick.kind == "lastused" then
                Report(Ring_Data.SetQuickSlice(ring.id, { kind = "first" }))
            elseif quick.kind == "first" then
                Report(Ring_Data.ClearQuickAction(ring.id))
            end
        end),
        -- Double-click on a submenu: scroll <-> spread.
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
            -- Untitled: the page only ever shows one ring (its name is in the sidebar).
            Setting_Widgets.Container(name .. ".Preview", {
                Frame(name .. ".PreviewHost")
                    :id("PreviewHost", id)
                    :size(UIKit.UI.P_FILL, Rings_Preview.HEIGHT)
            })
                :id("Preview", id),

            -- Shown in the preview's place while adding a slice.
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

            -- Delete Ring in its own untitled box, apart from the settings.
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

--- Setting_Enum.WidgetType.Custom builder. Also attaches the ring list to the sidebar, right under
--- this tab's button (the Menus tab is the last non-footer tab).
function Rings_Tab.Build(parent, tab)
    local page = Page("RLRM_RingsPage")
    page:parent(parent)
    page.tab = tab

    page.Settings:SetSubcontainer(false) -- container background art, as Build.Container does
    page.Settings.Title:SetText(L["Config - Rings - Settings - Title"])
    page.DeleteBox:SetSubcontainer(false)
    page.Preview:SetTransparent(true) -- wheel sits on the page background, no box
    page.AddSlice:Setup(function() return page:GetSelectedRing() end, function() page:ShowPreview() end)
    -- Moving between Options and our window changes how many results fit: re-render if open.
    -- Deferred a frame: the host change happens inside a UIKit render pass.
    CallbackRegistry.Add(Setting_Enum.Event.HostChanged, function()
        if not page.isAddingSlice then return end
        C_Timer.After(0, function()
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
    -- Import page. Its height changes as it fills: re-render next frame (it can
    -- happen inside a UIKit render pass, where queued frames would be dropped).
    local function RenderSoon() C_Timer.After(0, function() page.tab:_Render() end) end
    page.ImportPanel:Setup(RenderSoon, function(rings)
        if rings[1] then page.Nav:Select(rings[1].id) end
    end)
    page.ImportPanel:Hide()

    page.navTab = NAV_MINE
    page.Nav = Setting.AttachListNav(tab, {
        sections = {
            {
                title    = L["Config - Rings - Nav - Title"],
                tabs     = {
                    { id = NAV_MINE, text = L["Config - Rings - Nav - Mine"] },
                    { id = NAV_LIBRARY, text = L["Config - Rings - Nav - Library"] },
                },
                search   = { placeholder = L["Config - Rings - Nav - Search"] },
                getTab   = function() return page.navTab end,
                onTab    = function(tabId) page.navTab = tabId end,
                -- Side by side: both make menus.
                actions  = {
                    { text = L["Config - Rings - NewRing"], onClick = function() page:CreateNewRing() end },
                    { text = L["Config - Rings - Nav - Import"], onClick = function() page:ShowImport() end },
                },
                getItems = function()
                    if page.navTab == NAV_LIBRARY then return page:GetLibraryItems() end
                    return page:GetMyMenusItems()
                end,
            },
        },
        collapsed   = SavedCollapsedGroups(),
        -- No menu card lit while importing.
        getSelected = function() return not page.isImporting and page.selectedRingId or nil end,
        onSelect    = function(ringId) page:SelectRing(ringId) end,
    })

    tab:HookScript("OnHide", function()
        Rings_Keybind.CancelCapture()
        page:ShowPreview()
    end)

    -- Only while the settings are shown: automatic refills (bags, quests) happen all the time, and
    -- reopening the settings refreshes anyway (OnSettingRefresh).
    CallbackRegistry.Add(env.Event.DataChanged, function()
        if SettingFrame:IsVisible() then page:Refresh() end
    end)
    -- The preview center shows the last used slice for "Last Used Slice" rings.
    CallbackRegistry.Add(env.Event.LastUsedChanged, function()
        if SettingFrame:IsVisible() then page.preview:SetRing(page:GetSelectedRing()) end
    end)
    page:Refresh()

    return page
end
