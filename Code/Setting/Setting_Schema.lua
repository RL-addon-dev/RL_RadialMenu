--[[
    RL Radial Menu's settings: General, Menus and About tabs.

    Schema format (every widget type and field): libs\AX_Settings\README.md, with a full
    example in libs\AX_Settings\Examples\Schema.example.lua.
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local SavedVariables = env.AX_Modules:Import("ax_modules\\saved-variables")
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
    CallbackRegistry.Trigger("Config.Reset")
    CallbackRegistry.Trigger("Setting.Refresh")
end

-- Which Position / Appearance settings apply (Ring_Display loads after this file: read at refresh).
local function IsFixed() return Ring_Display.IsFixed() end
local function UsesCursorGuide() return Ring_Display.IsFixed() and not Ring_Display.IsSelectFromMenu() end
local function IsRelaxed() return Config.DBGlobal:GetVariable("MenuStyle") == env.Enum.MenuStyle.Relaxed end

-- Menu Style decides whether Reveal Delay shows.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "MenuStyle", function() CallbackRegistry.Trigger("Setting.Refresh") end)
-- Right-Click to Cancel changes how the Menu Style description says a Relaxed menu closes.
SavedVariables.OnChange("RL_RadialMenuDB_Global", "RightClickDismiss", function() CallbackRegistry.Trigger("Setting.Refresh") end)

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
                            key                      = "DisplayOpenAt"
                        },
                        {
                            widgetName               = L["Config - Display - SelectFrom"],
                            widgetDescription        = Setting_Define.Descriptor{ description = L["Config - Display - SelectFrom - Description"] },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.SelectFrom's order (Config.lua)
                                L["Config - Display - SelectFrom - Cursor"],
                                L["Config - Display - SelectFrom - Menu"]
                            },
                            key                      = "SelectFrom",
                            showWhen          = IsFixed
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
                            key                        = "DisplayScale"
                        },
                        {
                            widgetName        = L["Config - Display - ActionNames"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - ActionNames - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = "ShowActionNames"
                        },
                        {
                            widgetName        = L["Config - Display - ActionTooltips"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - ActionTooltips - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = "ShowActionTooltips"
                        },
                        {
                            widgetName        = L["Config - Display - CursorGuide"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - CursorGuide - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = "CursorGuide",
                            -- Not with Select From = Menu Center: there you point at the menu itself.
                            showWhen          = UsesCursorGuide
                        },
                        {
                            widgetName        = L["Config - Display - CursorGuideColor"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Display - CursorGuideColor - Description"] },
                            widgetType        = Setting_Enum.WidgetType.ColorInput,
                            key               = "CursorGuideColor",
                            showWhen          = function() return UsesCursorGuide() and Config.DBGlobal:GetVariable("CursorGuide") end
                        }
                    }
                },
                {
                    widgetName = L["Config - Behavior"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    children   = {
                        {
                            widgetName               = L["Config - Behavior - MenuStyle"],
                            widgetDescription        = Setting_Define.Descriptor{ description = function()
                                -- How a Relaxed menu closes depends on Right-Click to Cancel.
                                local key = "Config - Behavior - MenuStyle - Description"
                                if Config.DBGlobal:GetVariable("RightClickDismiss") then key = key .. " - RightClick" end
                                return L[key]
                            end },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.MenuStyle's order (Config.lua)
                                L["Config - Behavior - MenuStyle - Quick"],
                                L["Config - Behavior - MenuStyle - Relaxed"]
                            },
                            key                      = "MenuStyle"
                        },
                        {
                            widgetName                     = L["Config - Behavior - RevealDelay"],
                            widgetDescription              = Setting_Define.Descriptor{ description = L["Config - Behavior - RevealDelay - Description"] },
                            widgetType                     = Setting_Enum.WidgetType.Range,
                            widgetRange_min                = 0,
                            widgetRange_max                = 0.5,
                            widgetRange_step               = 0.05,
                            widgetRange_textFormattingFunc = function(value) return string.format("%.2fs", value) end,
                            key                            = "RevealDelay",
                            -- Relaxed menus show at once: there's no tap to wait for.
                            showWhen                       = function() return not IsRelaxed() end
                        },
                        {
                            widgetName                 = L["Config - Behavior - Deadzone"],
                            widgetDescription          = Setting_Define.Descriptor{ description = function() return BehaviorDescription("Deadzone") end },
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            widgetRange_min            = 8,
                            widgetRange_max            = 60,
                            widgetRange_step           = 1,
                            widgetRange_textFormatting = "%spx",
                            key                        = "Deadzone"
                        },
                        {
                            widgetName                 = L["Config - Behavior - ProbeSize"],
                            widgetDescription          = Setting_Define.Descriptor{ description = function() return BehaviorDescription("ProbeSize") end },
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            widgetRange_min            = 1,
                            widgetRange_max            = 60, -- the largest Distance to Select; with Select From Cursor, capped to the current one when used
                            widgetRange_step           = 1,
                            widgetRange_textFormatting = "%spx",
                            key                        = "ProbeSize"
                        },
                        {
                            widgetName        = L["Config - Behavior - RightClickDismiss"],
                            widgetDescription = Setting_Define.Descriptor{ description = L["Config - Behavior - RightClickDismiss - Description"] },
                            widgetType        = Setting_Enum.WidgetType.CheckButton,
                            key               = "RightClickDismiss"
                        },
                        {
                            widgetName               = L["Config - Behavior - WorldMarkerPlacement"],
                            widgetDescription        = Setting_Define.Descriptor{ description = L["Config - Behavior - WorldMarkerPlacement - Description"] },
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.WorldMarkerPlacement's order (Config.lua)
                                L["Config - Behavior - WorldMarkerPlacement - Mouse"],
                                L["Config - Behavior - WorldMarkerPlacement - Click"]
                            },
                            key                      = "WorldMarkerPlacement"
                        }
                    }
                },
                {
                    widgetName = nil,
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
