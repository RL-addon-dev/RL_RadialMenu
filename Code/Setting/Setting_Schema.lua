--[[
    RL Radial Menu's settings: General, Menus and About tabs.

    Schema format (every widget type and field): libs\AX_Settings\README.md, with a full
    example in libs\AX_Settings\Examples\Schema.example.lua.
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Setting_Define = env.AX_Modules:Import("@\\Setting\\Define")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Setting_Schema = env.AX_Modules:New("@\\Setting\\Schema")
local Ring_Display = env.AX_Modules:Await("@\\Ring\\Display")
local Rings_Tab = env.AX_Modules:Await("@\\Setting\\Rings\\Tab")

local SETTING_PROMPT = _G[Setting_Preload.FRAME_NAME].Prompt

--- Reset to default: settings only (menus live in the persistent saved variables).
local function HandleAccept()
    if not Config.DBGlobal then return end
    Config.DBGlobal:Wipe()
    -- Wipe doesn't fire per-key change callbacks; let listeners re-read everything.
    CallbackRegistry.Trigger(env.Event.ConfigReset)
    CallbackRegistry.Trigger(Setting_Enum.Event.Refresh)
end

-- Which Position / Appearance settings apply (Ring_Display loads after this file: read at refresh).
local function IsFixed() return Ring_Display.IsFixed() end
local function UsesCursorGuide() return Ring_Display.IsFixed() and not Ring_Display.IsSelectFromMenu() end
-- Menus work like Relaxed: the setting, or always in WoW Forever's gamepad UI (Ring_Secure).
local function IsRelaxed() return env.IsGamepadUI() or Config.Get(Config.Key.MenuStyle) == env.Enum.MenuStyle.Relaxed end
-- Playing with a controller (WoW Forever's gamepad UI): settings about the mouse are hidden (their
-- values still apply to menus opened with the keyboard or mouse), and controller ones shown.
local function IsController() return env.IsGamepadUI() end
local function IsMouse() return not env.IsGamepadUI() end

-- Menu Style decides whether Reveal Delay shows, and its own description.
Config.OnChange(Config.Key.MenuStyle, function() CallbackRegistry.Trigger(Setting_Enum.Event.Refresh) end)
-- Right-Click to Cancel changes how the Menu Style description says the menu cancels or closes.
Config.OnChange(Config.Key.RightClickDismiss, function() CallbackRegistry.Trigger(Setting_Enum.Event.Refresh) end)
-- Switching between the gamepad and the keyboard and mouse UI (WoW Forever) shows other settings.
do
    local styleWatcher = CreateFrame("Frame")
    if pcall(styleWatcher.RegisterEvent, styleWatcher, "INPUT_DEVICE_INTERFACE_TRANSITION") then
        styleWatcher:SetScript("OnEvent", function() CallbackRegistry.Trigger(Setting_Enum.Event.Refresh) end)
    end
end

--- Behavior settings describe distances from where they're measured: the key-down spot, or the
--- fixed menu's center with Select From = Menu Center.
local function BehaviorDescription(setting)
    local key = "Config - Behavior - " .. setting .. " - Description"
    if Ring_Display.IsSelectFromMenu() then key = key .. " - Menu" end
    return L[key]
end

local RESET_SETTING_PROMPT_INFO = {
    text         = L["Config - General - Other - ResetPrompt"],
    options      = {
        {
            text     = L["Config - General - Other - ResetPrompt - Yes"],
            callback = HandleAccept
        },
        {
            text     = L["Config - General - Other - ResetPrompt - No"],
            callback = nil
        }
    },
    hideOnEscape = true,
    timeout      = 10
}

do -- Schema
    Setting_Schema.SCHEMA = {
        {
            widgetName = L["Config - General"],
            widgetType = Setting_Enum.WidgetType.Tab,
            children   = {
                -- How a menu opens and closes.
                {
                    widgetName = L["Config - General - MenuStyle"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    children   = {
                        {
                            widgetName               = L["Config - Behavior - MenuStyle"],
                            widgetDescription        = Setting_Define.Descriptor{ description = function()
                                -- The chosen style's own description; how it cancels or closes
                                -- depends on Right-Click to Cancel.
                                local key = "Config - Behavior - MenuStyle - Description - " .. (IsRelaxed() and "Relaxed" or "Quick")
                                if Config.Get(Config.Key.RightClickDismiss) then key = key .. " - RightClick" end
                                return L[key]
                            end },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.MenuStyle's order (Config.lua)
                                L["Config - Behavior - MenuStyle - Quick"],
                                L["Config - Behavior - MenuStyle - Relaxed"]
                            },
                            key                      = Config.Key.MenuStyle,
                            -- With a controller, menus always work like Relaxed (A picks, B closes).
                            showWhen                 = IsMouse
                        },
                        {
                            widgetName        = L["Config - Behavior - FlickToSelect"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Behavior - FlickToSelect - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = Config.Key.FlickToSelect,
                            showWhen          = IsController
                        },
                        {
                            widgetName                     = L["Config - Behavior - RevealDelay"],
                            widgetDescription              = Setting_Define.Descriptor{ description = L["Config - Behavior - RevealDelay - Description"] },
                            widgetType                     = Setting_Enum.WidgetType.Range,
                            widgetRange_min                = 0,
                            widgetRange_max                = 0.5,
                            widgetRange_step               = 0.05,
                            widgetRange_textFormattingFunc = function(value) return string.format("%.2fs", value) end,
                            key                            = Config.Key.RevealDelay,
                            -- Relaxed menus show at once: there's no tap to wait for.
                            showWhen                       = function() return not IsRelaxed() end
                        },
                        {
                            widgetName        = L["Config - Behavior - RightClickDismiss"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Behavior - RightClickDismiss - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = Config.Key.RightClickDismiss,
                            showWhen          = IsMouse
                        }
                    }
                },
                -- How far the mouse moves to pick an action (the right stick's tilt is fixed).
                {
                    widgetName = L["Config - General - Selection"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    showWhen   = IsMouse,
                    children   = {
                        {
                            widgetName                 = L["Config - Behavior - Deadzone"],
                            widgetDescription          = Setting_Define.Descriptor{ description = function() return BehaviorDescription(Config.Key.Deadzone) end },
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            widgetRange_min            = 8,
                            widgetRange_max            = 60,
                            widgetRange_step           = 1,
                            widgetRange_textFormatting = "%spx",
                            key                        = Config.Key.Deadzone
                        },
                        {
                            widgetName                 = L["Config - Behavior - ProbeSize"],
                            widgetDescription          = Setting_Define.Descriptor{ description = function() return BehaviorDescription(Config.Key.ProbeSize) end },
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            widgetRange_min            = 1,
                            widgetRange_max            = 60, -- the largest Distance to Select; with Select From Cursor, capped to the current one when used
                            widgetRange_step           = 1,
                            widgetRange_textFormatting = "%spx",
                            key                        = Config.Key.ProbeSize
                        }
                    }
                },
                {
                    widgetName = L["Config - Display - Position"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    children   = {
                        {
                            widgetName               = L["Config - Display - OpenAt"],
                            widgetDescription        = Setting_Define.Descriptor{ description = L["Config - Display - OpenAt - Description"] },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.OpenAt's order (Config.lua)
                                L["Config - Display - OpenAt - Cursor"],
                                L["Config - Display - OpenAt - Fixed"]
                            },
                            key                      = Config.Key.DisplayOpenAt
                        },
                        {
                            widgetName               = L["Config - Display - SelectFrom"],
                            widgetDescription        = Setting_Define.Descriptor{ description = L["Config - Display - SelectFrom - Description"] },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.SelectFrom's order (Config.lua)
                                L["Config - Display - SelectFrom - Cursor"],
                                L["Config - Display - SelectFrom - Menu"]
                            },
                            key                      = Config.Key.SelectFrom,
                            -- The right stick picks by its own direction, wherever the menu is.
                            showWhen                 = function() return IsFixed() and IsMouse() end
                        },
                        {
                            widgetName        = L["Config - Display - EditMode"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - EditMode - Description"] },
                            widgetType        = Setting_Enum.WidgetType.Button,
                            widgetButton_text = L["Config - Display - EditMode - Button"],
                            set               = function() Ring_Display.OpenEditMode() end,
                            showWhen          = IsFixed
                        },
                        {
                            widgetName        = L["Config - Display - ResetPosition"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - ResetPosition - Description"] },
                            widgetType        = Setting_Enum.WidgetType.Button,
                            widgetButton_text = L["Config - Display - ResetPosition - Button"],
                            set               = function() Ring_Display.ResetPosition() end,
                            showWhen          = IsFixed
                        }
                    }
                },
                {
                    widgetName = L["Config - Display - Appearance"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    children   = {
                        {
                            widgetName                 = L["Config - Display - Scale"],
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            -- Same range as the Edit Mode slider (Ring_Display).
                            widgetRange_min            = function() return Ring_Display.SCALE_MIN end,
                            widgetRange_max            = function() return Ring_Display.SCALE_MAX end,
                            widgetRange_step           = function() return Ring_Display.SCALE_STEP end,
                            widgetRange_textFormatting = "%s%%",
                            key                        = Config.Key.DisplayScale
                        },
                        {
                            widgetName        = L["Config - Display - ActionNames"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - ActionNames - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = Config.Key.ShowActionNames
                        },
                        {
                            widgetName        = L["Config - Display - ActionTooltips"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - ActionTooltips - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = Config.Key.ShowActionTooltips
                        },
                        {
                            widgetName        = L["Config - Display - CursorGuide"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - CursorGuide - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = Config.Key.CursorGuide,
                            -- Not with Select From = Menu Center: there you point at the menu
                            -- itself. Nor with a controller: there's no mouse gesture to outline.
                            showWhen          = function() return UsesCursorGuide() and IsMouse() end
                        },
                        {
                            widgetName        = L["Config - Display - CursorGuideColor"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - CursorGuideColor - Description"] },
                            widgetType        = Setting_Enum.WidgetType.ColorInput,
                            key               = Config.Key.CursorGuideColor,
                            showWhen          = function() return UsesCursorGuide() and IsMouse() and Config.Get(Config.Key.CursorGuide) end
                        }
                    }
                },
                -- Target and world marker actions.
                {
                    widgetName = L["Config - General - Markers"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    children   = {
                        {
                            widgetName               = L["Config - Behavior - WorldMarkerPlacement"],
                            widgetDescription        = Setting_Define.Descriptor{ description = function()
                                -- The chosen option's own description.
                                local click = Config.Get(Config.Key.WorldMarkerPlacement) == env.Enum.WorldMarkerPlacement.Click
                                return L["Config - Behavior - WorldMarkerPlacement - Description - " .. (click and "Click" or "Mouse")]
                            end },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.WorldMarkerPlacement's order (Config.lua)
                                L["Config - Behavior - WorldMarkerPlacement - Mouse"],
                                L["Config - Behavior - WorldMarkerPlacement - Click"]
                            },
                            key                      = Config.Key.WorldMarkerPlacement,
                            -- With a controller, world markers are always placed with the reticle
                            -- (Kinds\WorldMarker.lua): there's no mouse to place them under.
                            showWhen                 = IsMouse
                        },
                        {
                            widgetName               = L["Config - Behavior - TargetMarkerUnit"],
                            widgetDescription        = Setting_Define.Descriptor{ description = function()
                                -- The chosen option's own description (the Cursor ones: their limits, in yellow).
                                -- With a controller, the cursor is the reticle.
                                local value = Config.Get(Config.Key.TargetMarkerUnit)
                                local suffix = IsController() and " - Controller" or ""
                                for name, enumValue in pairs(env.Enum.TargetMarkerUnit) do
                                    if enumValue == value and name ~= "Target" then
                                        return L["Config - Behavior - TargetMarkerUnit - Description - " .. name .. suffix]
                                    end
                                end
                                return L["Config - Behavior - TargetMarkerUnit - Description - Target"]
                            end },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = function() -- in env.Enum.TargetMarkerUnit's order (Config.lua)
                                local suffix = IsController() and " - Controller" or ""
                                return {
                                    L["Config - Behavior - TargetMarkerUnit - Target"],
                                    L["Config - Behavior - TargetMarkerUnit - Cursor" .. suffix],
                                    L["Config - Behavior - TargetMarkerUnit - CursorFocus" .. suffix]
                                }
                            end,
                            key                      = Config.Key.TargetMarkerUnit
                        }
                    }
                },
                {
                    widgetName = L["Config - General - Reset"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    children   = {
                        {
                            widgetName        = L["Config - General - Other - Reset - title"] ,
                            widgetType        = Setting_Enum.WidgetType.Button,
                            widgetButton_text = L["Config - General - Other - ResetButton"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - General - Other - Reset - Description"] },
                            set               = function() SETTING_PROMPT:Open(RESET_SETTING_PROMPT_INFO) end
                        }
                    }
                }
            }
        },
        {
            widgetName = L["Config - Rings"],
            widgetType = Setting_Enum.WidgetType.Tab,
            children   = {
                {
                    widgetType         = Setting_Enum.WidgetType.Custom,
                    widgetCustom_build = function(parent, tab) return Rings_Tab.Build(parent, tab) end
                }
            }
        },
        {
            widgetName         = L["Config - About"],
            widgetType         = Setting_Enum.WidgetType.Tab,
            widgetTab_isFooter = true,
            children           = {
                {
                    widgetName       = L["Config - About"],
                    widgetType       = Setting_Enum.WidgetType.Title,
                    widgetTitle_info = Setting_Define.TitleInfo{ imagePath = env.ICON, text = env.NAME_ALT, subtext = env.VERSION_STRING }
                },
                {
                    widgetName        = L["Config - About - Inspirations"],
                    widgetType        = Setting_Enum.WidgetType.Container,
                    widgetTransparent = true,
                    children          = {
                        {
                            widgetName        = L["Config - About - Inspirations - WaypointUI"],
                            widgetType        = Setting_Enum.WidgetType.Text,
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - About - Inspirations - WaypointUI - Description"] },
                            widgetTransparent = true
                        },
                        {
                            widgetName        = L["Config - About - Inspirations - Opie"],
                            widgetType        = Setting_Enum.WidgetType.Text,
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - About - Inspirations - Opie - Description"] },
                            widgetTransparent = true
                        },
                        {
                            -- Its technique keeps the right stick off the camera (Ring_Stick.lua);
                            -- also credited in README and NOTICE.
                            widgetName        = L["Config - About - Inspirations - ConsolePort"],
                            widgetType        = Setting_Enum.WidgetType.Text,
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - About - Inspirations - ConsolePort - Description"] },
                            widgetTransparent = true
                        },
                    }
                },
                {
                    -- Credit the CC BY 3.0 licence asks for (also README, NOTICE, Art\Symbols\CREDITS.md).
                    widgetName        = L["Config - About - Artwork"],
                    widgetType        = Setting_Enum.WidgetType.Container,
                    widgetTransparent = true,
                    children          = {
                        {
                            widgetName        = L["Config - About - Artwork - Symbols"],
                            widgetType        = Setting_Enum.WidgetType.Text,
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - About - Artwork - Symbols - Description"] },
                            widgetTransparent = true
                        }
                    }
                },
                {
                    widgetName        = L["Config - About - Developer"],
                    widgetType        = Setting_Enum.WidgetType.Container,
                    widgetTransparent = true,
                    children          = {
                        {
                            widgetName        = L["Config - About - Developer - Name"],
                            widgetType        = Setting_Enum.WidgetType.Text,
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - About - Developer - Name - Description"] },
                            widgetTransparent = true
                        }
                    }
                }
            }
        }
    }
end
