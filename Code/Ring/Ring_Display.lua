--[[
    Where the ring appears and how big it is. Shared by all rings.

    Settings (RL_RadialMenuDB_Global, also edited from the settings UI):
        DisplayOpenAt   env.Enum.OpenAt.Cursor | .Fixed
        DisplayScale    percent

    The fixed position is an Edit Mode frame (LibEditMode). Positions are saved per Edit Mode
    layout in RL_RadialMenuDB_Global_Persistent.EditModePositions[layoutName] = { point, x, y }.

    By default selection is relative to the cursor at key down (Ring_Secure), so a fixed ring is
    still controlled by gestures from wherever the mouse is. Select From = Menu Center measures
    from the fixed menu's center instead (IsSelectFromMenu, GetFixedCenter).
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local SavedVariables = env.AX_Modules:Import("ax_modules\\saved-variables")
local Setting = env.AX_Modules:Import("@\\Setting")
local LEM = env.LibEditMode
local Ring_Display = env.AX_Modules:New("@\\Ring\\Display")

local DB_GLOBAL_NAME = "RL_RadialMenuDB_Global"
local DEFAULT_POSITION = { point = "CENTER", x = 0, y = 0 }
local FALLBACK_SIZE = 375 -- RadialWheelFrameTemplate size
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 50, 200, 5

Ring_Display.SCALE_MIN = SCALE_MIN
Ring_Display.SCALE_MAX = SCALE_MAX
Ring_Display.SCALE_STEP = SCALE_STEP



-- Settings

function Ring_Display.GetOpenAt()
    return Config.DBGlobal:GetVariable("DisplayOpenAt")
end

function Ring_Display.SetOpenAt(value)
    Config.DBGlobal:SetVariable("DisplayOpenAt", value)
end

function Ring_Display.IsFixed()
    return Ring_Display.GetOpenAt() == env.Enum.OpenAt.Fixed
end

--- Fixed position with Select From = Menu Center: actions are picked by where the cursor is
--- relative to the menu's center instead of by the direction moved from the key-down spot.
function Ring_Display.IsSelectFromMenu()
    return Ring_Display.IsFixed() and Config.DBGlobal:GetVariable("SelectFrom") == env.Enum.SelectFrom.Menu
end

--- @return number scale multiplier (1 = 100%)
function Ring_Display.GetScale()
    return (Config.DBGlobal:GetVariable("DisplayScale") or 100) / 100
end

function Ring_Display.SetScalePercent(value)
    Config.DBGlobal:SetVariable("DisplayScale", value)
end



-- Edit Mode anchor

local Anchor = CreateFrame("Frame", "RLRM_RingAnchor", UIParent)
Anchor.editModeName = env.NAME_ALT
Anchor:SetPoint(DEFAULT_POSITION.point, UIParent, DEFAULT_POSITION.point, DEFAULT_POSITION.x, DEFAULT_POSITION.y)
Anchor:SetFrameStrata("FULLSCREEN_DIALOG")
Anchor:SetClampedToScreen(true)

-- Shown only while Edit Mode is open, so the user can see the ring's footprint.
Anchor.Preview = Anchor:CreateTexture(nil, "BACKGROUND")
Anchor.Preview:SetAllPoints()
Anchor.Preview:SetAtlas("Radial_Wheel_BG")
Anchor.Preview:Hide()

local function GetBaseSize()
    local info = C_Texture.GetAtlasInfo("Radial_Wheel_BG")
    return info and info.width or FALLBACK_SIZE, info and info.height or FALLBACK_SIZE
end

--- The fixed menu's center may have moved (position, size, UI scale, layout): Ring_Secure keeps a
--- copy for Select From = Menu Center.
local function NotifyMoved()
    CallbackRegistry.Trigger("Ring.DisplayMoved")
end

local function UpdateAnchorSize()
    local width, height = GetBaseSize()
    local scale = Ring_Display.GetScale()
    Anchor:SetSize(width * scale, height * scale)
    NotifyMoved()
end

local function GetSavedPositions()
    local stored = _G[Config.DBGlobalPersistent.databaseName]
    if type(stored.EditModePositions) ~= "table" then stored.EditModePositions = {} end
    return stored.EditModePositions
end

--- The active Edit Mode layout's name. Not LibEditMode's: it assumes two presets (Modern,
--- Classic), but Blizzard numbers all its presets first, then the custom layouts.
local function GetActiveLayoutName()
    local info, presets = C_EditMode.GetLayouts(), EditModePresetLayoutManager.presetLayoutInfo
    if info.activeLayout <= 2 then return info.activeLayout == 1 and "Modern" or "Classic" end -- LibEditMode's names
    local layout = presets[info.activeLayout] or info.layouts[info.activeLayout - #presets]
    return layout and layout.layoutName
end

--- Moves the anchor to its saved position in the active Edit Mode layout (default if none).
local function ApplyPosition()
    local layoutName = GetActiveLayoutName()
    local position = (layoutName and GetSavedPositions()[layoutName]) or DEFAULT_POSITION
    Anchor:ClearAllPoints()
    Anchor:SetPoint(position.point, UIParent, position.point, position.x, position.y)
    NotifyMoved()
end

--- LibEditMode: the anchor was dragged in the active layout.
local function OnPositionChanged(frame, _, point, x, y)
    local layoutName = GetActiveLayoutName()
    if not layoutName then return end
    GetSavedPositions()[layoutName] = { point = point, x = x, y = y }
    ApplyPosition()
end

function Ring_Display.ResetPosition()
    local layoutName = GetActiveLayoutName()
    if layoutName then GetSavedPositions()[layoutName] = nil end
    ApplyPosition()
end

function Ring_Display.OpenEditMode()
    if InCombatLockdown() then
        env.Print(L["Config - Display - EditMode - Combat"])
        return
    end
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    Setting.CloseWindow()
    ShowUIPanel(EditModeManagerFrame)
end

--- Center of the fixed menu in UIParent coordinates, or nil (not fixed, or not placed yet).
function Ring_Display.GetFixedCenter()
    if not Ring_Display.IsFixed() then return nil end
    return Anchor:GetCenter()
end

--- Center of the ring in UIParent coordinates.
--- @param cursorX number cursor x at key down (UIParent units)
--- @param cursorY number
function Ring_Display.GetCenter(cursorX, cursorY)
    if Ring_Display.IsFixed() then
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
    CallbackRegistry.Trigger("Setting.Refresh")
end

local function Initialize()
    UpdateAnchorSize()

    LEM:AddFrame(Anchor, OnPositionChanged, DEFAULT_POSITION, env.NAME_ALT)
    LEM:AddFrameSettings(Anchor, {
        {
            name    = L["Config - Display - OpenAt"],
            desc    = L["Config - Display - OpenAt - Description"],
            kind    = LEM.SettingType.Dropdown,
            default = env.Enum.OpenAt.Cursor,
            values  = {
                { text = L["Config - Display - OpenAt - Cursor"], value = env.Enum.OpenAt.Cursor },
                { text = L["Config - Display - OpenAt - Fixed"],  value = env.Enum.OpenAt.Fixed },
            },
            get     = function() return Ring_Display.GetOpenAt() end,
            set     = function(_, value) Ring_Display.SetOpenAt(value) end
        },
        {
            name      = L["Config - Display - Scale"],
            desc      = L["Config - Display - Scale - Description"],
            kind      = LEM.SettingType.Slider,
            default   = 100,
            minValue  = SCALE_MIN,
            maxValue  = SCALE_MAX,
            valueStep = SCALE_STEP,
            get       = function() return Config.DBGlobal:GetVariable("DisplayScale") end,
            set       = function(_, value) Ring_Display.SetScalePercent(value) end
        }
    })

    LEM:RegisterCallback("layout", ApplyPosition)
    LEM:RegisterCallback("enter", function() Anchor.Preview:Show() end)
    LEM:RegisterCallback("exit", function() Anchor.Preview:Hide() end)

    SavedVariables.OnChange(DB_GLOBAL_NAME, "DisplayScale", OnSettingChanged)
    SavedVariables.OnChange(DB_GLOBAL_NAME, "DisplayOpenAt", OnSettingChanged)
    SavedVariables.OnChange(DB_GLOBAL_NAME, "SelectFrom", OnSettingChanged)
    CallbackRegistry.Add("Config.Reset", OnSettingChanged)

    -- UIParent's size in UI units changes with the UI scale / window size, and with it the
    -- center's coordinates.
    local scaleEvents = CreateFrame("Frame")
    scaleEvents:RegisterEvent("UI_SCALE_CHANGED")
    scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleEvents:SetScript("OnEvent", NotifyMoved)
end

CallbackRegistry.Add("Preload.DatabaseReady", Initialize)
