local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Setting_Constructor = env.AX_Modules:Await("@\\Setting\\Constructor")
local Setting_Options = env.AX_Modules:Import("@\\Setting\\Options")
local Setting = env.AX_Modules:New("@\\Setting")

local SettingFrame = _G[Setting_Preload.FRAME_NAME]
local SettingsCanvas = SettingsPanel.Container.SettingsCanvas
local IsAddonLoaded = C_AddOns.IsAddOnLoaded



local isElvUILoaded = false
local selectedTabIndex = nil
local categoryId = nil

function Setting:OpenTabByIndex(index)
    selectedTabIndex = index

    for i = 1, #Setting_Constructor.Tabs do
        local tab = Setting_Constructor.Tabs[i]
        local tabButton = Setting_Constructor.TabButtons[i]
        local isSelected = i == index

        if isSelected and not tab:IsShown() then tab:PlayIntro() end
        tab:SetShown(isSelected)
        tabButton:SetSelected(isSelected)

        if isSelected and not tab.hasRendered then
            tab:_Render()
            tab.hasRendered = true
        end

        Setting_Constructor:Refresh(true)
    end
end



--[[
    The settings frame has two hosts and moves to whichever is shown:
        Options → AddOns   SettingFrameAnchor, a canvas category inside Blizzard's Settings panel
        own window         SettingWindow, toggled by Setting.OpenSettingUI (the addon hooks it to a
                           slash command, the addon drawer, ...). Blizzard disables the spellbook,
                           bags, collections etc. while its Settings panel is open, so dragging from
                           them into the settings needs this window.
]]

local SettingFrameAnchor = CreateFrame("Frame", nil, UIParent)
local SettingFrameInset = 8
local isInitialized = false
local currentHost = nil

local WINDOW_WIDTH, WINDOW_HEIGHT = 820, 660
local WINDOW_CONTENT_INSETS = { left = 10, right = -6, top = -24, bottom = 6 }
local WINDOW_DRAG_HEIGHT = 22

local RenderUI

local function SetupSettingUI()
    Setting_Constructor:SetBuildTargetFrame(SettingFrame.Content.Container)
    Setting_Constructor:Build(Setting_Options.getSchema())
    SettingFrame:_Render()
    Setting:OpenTabByIndex(1)
end

--- Reparenting resets children to the new parent's strata; the dropdown list must stay above
--- the settings (it's created at FULLSCREEN_DIALOG), so pin it.
local function KeepPopupsOnTop()
    local menu = SettingFrame.SelectionMenu
    if menu then
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFixedFrameStrata(true)
        menu:Raise()
    end
end

--- Where the settings are shown right now: "options" (Options -> AddOns), "window" (the own
--- window), or nil while closed. "Setting.HostChanged" fires on change.
function Setting.GetHost()
    if not currentHost then return nil end
    return currentHost == SettingFrameAnchor and "options" or "window"
end

--- Moves the settings frame into `host` and fills it.
local function AttachTo(host)
    local changed = currentHost ~= host
    currentHost = host
    SettingFrame:SetParent(host)
    KeepPopupsOnTop()
    SettingFrame:ClearAllPoints()
    SettingFrame:SetPoint("CENTER", host)
    SettingFrame:SetSize(host:GetSize())
    SettingFrame:Show()

    if not isInitialized then
        SetupSettingUI()
        isInitialized = true
        -- The first layout runs before text has wrapped to its final size, so content heights
        -- (and the scroll range) come out short. Lay out again once it has, like every later open.
        C_Timer.After(0, function() C_Timer.After(0, RenderUI) end)
    else
        -- The host may have a different size: relayout, then pull values changed elsewhere
        -- (e.g. Edit Mode). Not forced: a forced refresh reuses the cached value.
        RenderUI()
        CallbackRegistry.Trigger("Setting.Refresh")
    end
    if changed then CallbackRegistry.Trigger("Setting.HostChanged", Setting.GetHost()) end
end

local function DetachFrom(host)
    if currentHost ~= host then return end
    currentHost = nil
    SettingFrame:Hide()
    CallbackRegistry.Trigger("Setting.HostChanged", nil)
end



-- Own window

local SettingWindow = CreateFrame("Frame", Setting_Preload.WINDOW_NAME, UIParent, "SettingsFrameTemplate")
SettingWindow:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
SettingWindow:SetPoint("CENTER")
SettingWindow:SetFrameStrata("HIGH")
SettingWindow:SetToplevel(true)
SettingWindow:SetMovable(true)
SettingWindow:SetClampedToScreen(true)
SettingWindow:EnableMouse(true)
SettingWindow:Hide()
SettingWindow.NineSlice.Text:SetText(Setting_Options.title)
tinsert(UISpecialFrames, SettingWindow:GetName()) -- Esc closes it

-- Plain hide: the template's close button goes through the UI panel manager.
SettingWindow.ClosePanelButton:SetScript("OnClick", function() SettingWindow:Hide() end)

SettingWindow.Content = CreateFrame("Frame", nil, SettingWindow)
SettingWindow.Content:SetPoint("TOPLEFT", WINDOW_CONTENT_INSETS.left, WINDOW_CONTENT_INSETS.top)
SettingWindow.Content:SetPoint("BOTTOMRIGHT", WINDOW_CONTENT_INSETS.right, WINDOW_CONTENT_INSETS.bottom)

local function SaveWindowPosition()
    local store = Setting_Options.windowPosition
    if not store then return end
    local point, _, relativePoint, x, y = SettingWindow:GetPoint(1)
    store.set({ point = point, relativePoint = relativePoint, x = x, y = y })
end

local function RestoreWindowPosition()
    local store = Setting_Options.windowPosition
    local position = store and store.get()
    if not position then return end
    SettingWindow:ClearAllPoints()
    SettingWindow:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
end

-- Drag by the title bar only, so dragging inside the settings (e.g. reordering items) doesn't move it.
local DragHandle = CreateFrame("Frame", nil, SettingWindow)
DragHandle:SetPoint("TOPLEFT", 0, 0)
DragHandle:SetPoint("TOPRIGHT", -24, 0)
DragHandle:SetHeight(WINDOW_DRAG_HEIGHT)
DragHandle:EnableMouse(true)
DragHandle:RegisterForDrag("LeftButton")
DragHandle:SetScript("OnDragStart", function() SettingWindow:StartMoving() end)
DragHandle:SetScript("OnDragStop", function()
    SettingWindow:StopMovingOrSizing()
    SaveWindowPosition()
end)

SettingWindow:SetScript("OnShow", function(self)
    RestoreWindowPosition()
    AttachTo(self.Content)
end)
SettingWindow:SetScript("OnHide", function(self)
    DetachFrom(self.Content)
end)

--- Toggles the own window.
function Setting.OpenSettingUI()
    SettingWindow:SetShown(not SettingWindow:IsShown())
end

--- Closes the own window if it's open (e.g. before opening Edit Mode).
function Setting.CloseWindow()
    if SettingWindow:IsShown() then SettingWindow:Hide() end
end



-- Options → AddOns host

local function OnShow(self)
    if not isElvUILoaded then isElvUILoaded = IsAddonLoaded("ElvUI") end

    SettingFrameAnchor:ClearAllPoints()
    if isElvUILoaded then
        SettingFrameAnchor:SetAllPoints(SettingsCanvas)
    else
        SettingFrameAnchor:SetPoint("CENTER", SettingsCanvas, -SettingFrameInset, SettingFrameInset)
        SettingFrameAnchor:SetSize(math.ceil(SettingsCanvas:GetWidth() + SettingFrameInset * 2), math.ceil(SettingsCanvas:GetHeight() + SettingFrameInset / 2))
    end

    -- One settings frame: showing it in Options takes it out of the own window.
    if SettingWindow:IsShown() then SettingWindow:Hide() end
    AttachTo(SettingFrameAnchor)
end

local function OnHide(self)
    DetachFrom(SettingFrameAnchor)
end

RenderUI = function()
    if SettingFrame:IsShown() and isInitialized then
        SettingFrame:_Render()

        for i = 1, #Setting_Constructor.Tabs do
            Setting_Constructor.Tabs[i].hasRendered = false
        end

        local currentTab = selectedTabIndex and Setting_Constructor.Tabs[selectedTabIndex]
        if currentTab then
            currentTab.hasRendered = true
            currentTab:_Render()
        end
    end
end

SettingFrameAnchor:HookScript("OnShow", OnShow)
SettingFrameAnchor:HookScript("OnHide", OnHide)
SettingFrameAnchor:SetScript("OnEvent", RenderUI)
CallbackRegistry.Add("WoWClient.OnUIScaleChanged", RenderUI)



local function OnAddonLoaded()
    SettingFrameAnchor:Hide()
    SettingFrame:Hide()

    local category = Settings.RegisterCanvasLayoutCategory(SettingFrameAnchor, Setting_Preload.NAME)
    Settings.RegisterAddOnCategory(category)
    categoryId = category:GetID()
end
CallbackRegistry.Add("WoWClient.OnAddonLoaded", OnAddonLoaded)
