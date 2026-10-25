--[[
    Menu_Display: where the menus appear and how big they are. It's the same for every menu.

    The settings (Config.Key, also edited from the settings window).
        DisplayOpenAt   env.Enum.OpenAt.Cursor or .Fixed
        DisplayScale    a percent

    The fixed position is an Edit Mode frame (LibEditMode). Positions are saved per Edit Mode
    layout, as RL_RadialMenuDB_Global_Persistent.EditModePositions[layoutName] = { point, x, y }.

    By default, the pick is relative to the cursor at key down (Menu_Secure), so a fixed menu is
    still steered by gestures from wherever the mouse is. Select From = Menu Center measures from
    the fixed menu's center instead (IsSelectFromMenu, GetFixedCenter).
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Setting = env.AX_Modules:Import("@\\Setting")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local LEM = env.LibEditMode
local Menu_Display = env.AX_Modules:New("@\\Menu\\Display")

local DEFAULT_POSITION = { point = "CENTER", x = 0, y = 0 }
local ATLAS_BACKGROUND = "Radial_Wheel_BG" -- the wheel's shade (Menu_Layout), for the Edit Mode footprint
local FALLBACK_SIZE = 375 -- RadialWheelFrameTemplate's size
local SCALE_DEFAULT, SCALE_MIN, SCALE_MAX, SCALE_STEP = 100, 50, 200, 5
-- LibEditMode's names for Blizzard's first two preset layouts. They're saved data (the keys of
-- EditModePositions), so they never change.
local LAYOUT_MODERN, LAYOUT_CLASSIC = "Modern", "Classic"

Menu_Display.SCALE_MIN = SCALE_MIN
Menu_Display.SCALE_MAX = SCALE_MAX
Menu_Display.SCALE_STEP = SCALE_STEP



-- Settings

--- The Open At setting (env.Enum.OpenAt).
---@return integer
function Menu_Display.GetOpenAt()
    return Config.Get(Config.Key.DisplayOpenAt)
end

--- Whether menus open at the fixed position, not at the cursor.
---@return boolean
function Menu_Display.IsFixed()
    return Menu_Display.GetOpenAt() == env.Enum.OpenAt.Fixed
end

--- Whether actions are picked by where the cursor is relative to the fixed menu's center, instead
--- of by the direction it moved from the key down spot (a fixed position with Select From = Menu
--- Center).
---@return boolean
function Menu_Display.IsSelectFromMenu()
    return Menu_Display.IsFixed() and Config.Get(Config.Key.SelectFrom) == env.Enum.SelectFrom.Menu
end

--- The menus' size, as a multiplier (1 is 100%).
---@return number
function Menu_Display.GetScale()
    return (Config.Get(Config.Key.DisplayScale) or SCALE_DEFAULT) / 100
end

--- Saves the menus' size, in percent.
---@param value number
function Menu_Display.SetScalePercent(value)
    Config.Set(Config.Key.DisplayScale, value)
end



-- Edit Mode anchor

--- The fixed menu's Edit Mode frame.
---@class MenuDisplayAnchor : Frame
---@field editModeName string the name Edit Mode shows (LibEditMode)
---@field Preview Texture the menu's footprint, shown while Edit Mode is open

local Anchor = CreateFrame("Frame", "RLRM_MenuAnchor", UIParent) --[[@as MenuDisplayAnchor]]
Anchor.editModeName = env.NAME_ALT
Anchor:SetPoint(DEFAULT_POSITION.point, UIParent, DEFAULT_POSITION.point, DEFAULT_POSITION.x, DEFAULT_POSITION.y)
Anchor:SetFrameStrata("FULLSCREEN_DIALOG")
Anchor:SetClampedToScreen(true)

-- Shown only while Edit Mode is open, so you can see the menu's footprint.
Anchor.Preview = Anchor:CreateTexture(nil, "BACKGROUND")
Anchor.Preview:SetAllPoints()
Anchor.Preview:SetAtlas(ATLAS_BACKGROUND)
Anchor.Preview:Hide()

--- The menu's size at 100%.
---@return number width
---@return number height
local function GetBaseSize()
    local info = C_Texture.GetAtlasInfo(ATLAS_BACKGROUND)
    return info and info.width or FALLBACK_SIZE, info and info.height or FALLBACK_SIZE
end

--- Tells Menu_Secure the fixed menu's center may have moved (position, size, UI scale, layout),
--- since it keeps a copy for Select From = Menu Center.
local function NotifyMoved()
    CallbackRegistry.Trigger(env.Event.DisplayMoved)
end

--- Sizes the Edit Mode frame like the menu at the current scale.
local function UpdateAnchorSize()
    local width, height = GetBaseSize()
    local scale = Menu_Display.GetScale()
    Anchor:SetSize(width * scale, height * scale)
    NotifyMoved()
end

--- The saved positions, by Edit Mode layout name.
---@return table<string, { point: string, x: number, y: number }>
local function GetSavedPositions()
    local stored = Config.DBGlobalPersistent:GetData()
    if type(stored.EditModePositions) ~= "table" then stored.EditModePositions = {} end
    return stored.EditModePositions
end

--- The active Edit Mode layout's name. It's not LibEditMode's own lookup, which assumes two
--- presets, while Blizzard numbers all its presets first, then the custom layouts.
---@return string?
local function GetActiveLayoutName()
    local info, presets = C_EditMode.GetLayouts(), EditModePresetLayoutManager.presetLayoutInfo
    if info.activeLayout <= 2 then return info.activeLayout == 1 and LAYOUT_MODERN or LAYOUT_CLASSIC end
    local layout = presets[info.activeLayout] or info.layouts[info.activeLayout - #presets]
    return layout and layout.layoutName
end

--- Moves the anchor to its saved position in the active Edit Mode layout (the default if none).
local function ApplyPosition()
    local layoutName = GetActiveLayoutName()
    local position = (layoutName and GetSavedPositions()[layoutName]) or DEFAULT_POSITION
    Anchor:ClearAllPoints()
    Anchor:SetPoint(position.point, UIParent, position.point, position.x, position.y)
    NotifyMoved()
end

--- Called by LibEditMode when the anchor was dragged in the active layout.
---@param point string
---@param x number
---@param y number
local function OnPositionChanged(_, _, point, x, y)
    local layoutName = GetActiveLayoutName()
    if not layoutName then return end
    GetSavedPositions()[layoutName] = { point = point, x = x, y = y }
    ApplyPosition()
end

--- Puts the fixed menu back at the default position, in the active Edit Mode layout.
function Menu_Display.ResetPosition()
    local layoutName = GetActiveLayoutName()
    if layoutName then GetSavedPositions()[layoutName] = nil end
    ApplyPosition()
end

--- Opens Edit Mode, closing the settings windows (not in combat).
function Menu_Display.OpenEditMode()
    if InCombatLockdown() then
        env.Print(L["Config - Display - EditMode - Combat"])
        return
    end
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    Setting.CloseWindow()
    ShowUIPanel(EditModeManagerFrame)
end

--- The fixed menu's center in UIParent coordinates, or nil (not fixed, or not placed yet).
---@return number? x
---@return number? y
function Menu_Display.GetFixedCenter()
    if not Menu_Display.IsFixed() then return nil end
    return Anchor:GetCenter()
end

--- Where the menu's center goes, in UIParent coordinates.
---@param cursorX number the cursor at key down (UIParent units)
---@param cursorY number
---@return number x
---@return number y
function Menu_Display.GetCenter(cursorX, cursorY)
    if Menu_Display.IsFixed() then
        local x, y = Anchor:GetCenter()
        if x and y then return x, y end
    end
    return cursorX, cursorY
end



-- Registration

local function RefreshEditModeSettings()
    if LEM:IsInEditMode() then LEM:RefreshFrameSettings(Anchor) end
end

local function OnSettingChanged()
    UpdateAnchorSize()
    RefreshEditModeSettings()
    CallbackRegistry.Trigger(Setting_Enum.Event.Refresh)
end

local function Initialize()
    UpdateAnchorSize()

    LEM:AddFrame(Anchor, OnPositionChanged, DEFAULT_POSITION, env.NAME_ALT)
    -- Only the size here (and LibEditMode's Reset Position). The rest is in the addon's settings.
    LEM:AddFrameSettings(Anchor, {
        {
            name      = L["Config - Display - Scale"],
            desc      = L["Config - Display - Scale - Description"],
            kind      = LEM.SettingType.Slider,
            default   = SCALE_DEFAULT,
            minValue  = SCALE_MIN,
            maxValue  = SCALE_MAX,
            valueStep = SCALE_STEP,
            get       = function() return Config.Get(Config.Key.DisplayScale) end,
            set       = function(_, value) Menu_Display.SetScalePercent(value) end
        }
    })

    -- LibEditMode always adds Reset To Default under a frame's settings (every setting back to its
    -- default). It's hidden for this frame, where it would only reset the size. That's done after
    -- the dialog fills itself, because the dialog is shared with any other frame of this copy, so
    -- it's shown again for them.
    local dialog = LEM.internal and LEM.internal.dialog
    if dialog and dialog.UpdateSettings then
        hooksecurefunc(dialog, "UpdateSettings", function(self)
            local resetButton = self.Settings and self.Settings.ResetButton
            if resetButton then resetButton:SetShown(not (self.selection and self.selection.parent == Anchor)) end
        end)
    end

    LEM:RegisterCallback("layout", ApplyPosition)
    LEM:RegisterCallback("enter", function() Anchor.Preview:Show() end)
    LEM:RegisterCallback("exit", function() Anchor.Preview:Hide() end)

    Config.OnChange(Config.Key.DisplayScale, OnSettingChanged)
    Config.OnChange(Config.Key.DisplayOpenAt, OnSettingChanged)
    Config.OnChange(Config.Key.SelectFrom, OnSettingChanged)
    CallbackRegistry.Add(env.Event.ConfigReset, OnSettingChanged)

    -- UIParent's size in UI units changes with the UI scale and the window size, and with it the
    -- center's coordinates.
    local scaleEvents = CreateFrame("Frame")
    scaleEvents:RegisterEvent("UI_SCALE_CHANGED")
    scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleEvents:SetScript("OnEvent", NotifyMoved)
end

CallbackRegistry.Add(env.Event.DatabaseReady, Initialize)
