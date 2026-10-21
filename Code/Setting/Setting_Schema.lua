--[[
    Setting_Schema: RL Radial Menu's settings, in the General, Menus and About tabs.

    The schema's format (every widget type and field) is in libs\AX_Settings\README.md, with a
    full example in libs\AX_Settings\Examples\Schema.example.lua.
]]

local env = select(2, ...)
local Config = env.Config
local L = env.L
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Setting_Define = env.AX_Modules:Import("@\\Setting\\Define")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Setting_Schema = env.AX_Modules:New("@\\Setting\\Schema")
local Menu_Display = env.AX_Modules:Await("@\\Menu\\Display")
local Menus_Tab = env.AX_Modules:Await("@\\Setting\\Menus\\Tab")

local SETTING_PROMPT = _G[Setting_Preload.FRAME_NAME].Prompt

-- The settings shown again, for rows that show and hide or whose description changes.
local function RefreshShown()
    CallbackRegistry.Trigger(Setting_Enum.Event.Refresh)
end

--- Resets every setting to its default, but not the menus (they live in the persistent saved
--- variables).
local function HandleAccept()
    if not Config.DBGlobal then return end
    Config.DBGlobal:Wipe()
    -- Wipe doesn't fire each key's change callbacks, so listeners read everything again.
    CallbackRegistry.Trigger(env.Event.ConfigReset)
    RefreshShown()
end

-- Which Position and Appearance settings apply. Menu_Display loads after this file, so they're
-- read when the settings refresh.
local function IsFixed() return Menu_Display.IsFixed() end
local function UsesCursorGuide() return Menu_Display.IsFixed() and not Menu_Display.IsSelectFromMenu() end
-- Menus work like Relaxed with the setting, or always in WoW Forever's gamepad UI (Menu_Secure).
local function IsRelaxed() return env.IsGamepadUI() or Config.Get(Config.Key.MenuStyle) == env.Enum.MenuStyle.Relaxed end
-- Playing with a controller (WoW Forever's gamepad UI), settings about the mouse are hidden (their
-- values still apply to menus opened with the keyboard or mouse), and controller ones shown.
local function IsController() return env.IsGamepadUI() end
local function IsMouse() return not env.IsGamepadUI() end

-- Menu Style decides whether Reveal Delay shows, and its own description.
Config.OnChange(Config.Key.MenuStyle, RefreshShown)
-- Right-Click to Cancel changes how the Menu Style description says the menu cancels or closes.
Config.OnChange(Config.Key.RightClickDismiss, RefreshShown)
-- Switching between the gamepad and the keyboard and mouse UI (WoW Forever) shows other settings.
do
    local styleWatcher = CreateFrame("Frame")
    if pcall(styleWatcher.RegisterEvent, styleWatcher, "INPUT_DEVICE_INTERFACE_TRANSITION") then
        styleWatcher:SetScript("OnEvent", RefreshShown)
    end
end



-- Row builders

--- A row's description (text, or a function giving it when the settings refresh).
---@param text string|function
---@return table
local function Description(text)
    return Setting_Define.Descriptor{ description = text }
end

--- A checkbox row. Its name is L[nameKey], and its description L[nameKey .. " - Description"].
---@param nameKey string
---@param key string a Config.Key value
---@param showWhen function?
---@return table
local function CheckButton(nameKey, key, showWhen)
    return {
        widgetName        = L[nameKey],
        widgetDescription = Description(L[nameKey .. " - Description"]),
        widgetType        = Setting_Enum.WidgetType.CheckButton,
        key               = key,
        showWhen          = showWhen
    }
end

--- A button row. Its name is L[nameKey], its description L[nameKey .. " - Description"], and its
--- button's text L[nameKey .. " - Button"].
---@param nameKey string
---@param onClick function
---@param showWhen function?
---@return table
local function Button(nameKey, onClick, showWhen)
    return {
        widgetName        = L[nameKey],
        widgetDescription = Description(L[nameKey .. " - Description"]),
        widgetType        = Setting_Enum.WidgetType.Button,
        widgetButton_text = L[nameKey .. " - Button"],
        set               = onClick,
        showWhen          = showWhen
    }
end

--- An About tab text row, on the page's background. Its name is L[nameKey], and its text
--- L[nameKey .. " - Description"].
---@param nameKey string
---@return table
local function Credit(nameKey)
    return {
        widgetName        = L[nameKey],
        widgetType        = Setting_Enum.WidgetType.Text,
        widgetDescription = Description(L[nameKey .. " - Description"]),
        widgetTransparent = true
    }
end

--- An About tab group, on the page's background.
---@param nameKey string
---@param children table[]
---@return table
local function AboutGroup(nameKey, children)
    return {
        widgetName        = L[nameKey],
        widgetType        = Setting_Enum.WidgetType.Container,
        widgetTransparent = true,
        children          = children
    }
end

--- Behavior settings describe distances from where they're measured: the key down spot, or the
--- fixed menu's center with Select From = Menu Center.
---@param setting string a Config.Key value
---@return string
local function BehaviorDescription(setting)
    -- "Config - Behavior - <setting> - Description", and its " - Menu" form.
    local key = "Config - Behavior - " .. setting .. " - Description"
    if Menu_Display.IsSelectFromMenu() then key = key .. " - Menu" end
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
                            widgetDescription        = Description(function()
                                -- The chosen style's own description. How it cancels or closes
                                -- depends on Right-Click to Cancel. That's "Config - Behavior -
                                -- MenuStyle - Description - Quick" or "- Relaxed", and each one's
                                -- " - RightClick" form.
                                local key = "Config - Behavior - MenuStyle - Description - " .. (IsRelaxed() and "Relaxed" or "Quick")
                                if Config.Get(Config.Key.RightClickDismiss) then key = key .. " - RightClick" end
                                return L[key]
                            end),
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.MenuStyle's order (Config.lua)
                                L["Config - Behavior - MenuStyle - Quick"],
                                L["Config - Behavior - MenuStyle - Relaxed"]
                            },
                            key                      = Config.Key.MenuStyle,
                            -- With a controller, menus always work like Relaxed (A picks, B closes).
                            showWhen                 = IsMouse
                        },
                        CheckButton("Config - Behavior - FlickToSelect", Config.Key.FlickToSelect, IsController),
                        {
                            widgetName                     = L["Config - Behavior - RevealDelay"],
                            widgetDescription              = Description(L["Config - Behavior - RevealDelay - Description"]),
                            widgetType                     = Setting_Enum.WidgetType.Range,
                            widgetRange_min                = 0,
                            widgetRange_max                = 0.5,
                            widgetRange_step               = 0.05,
                            widgetRange_textFormattingFunc = function(value) return string.format("%.2fs", value) end,
                            key                            = Config.Key.RevealDelay,
                            -- Relaxed menus show at once, with no tap to wait for.
                            showWhen                       = function() return not IsRelaxed() end
                        },
                        CheckButton("Config - Behavior - RightClickDismiss", Config.Key.RightClickDismiss, IsMouse)
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
                            widgetDescription          = Description(function() return BehaviorDescription(Config.Key.Deadzone) end),
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            widgetRange_min            = Config.DEADZONE_MIN,
                            widgetRange_max            = Config.DEADZONE_MAX,
                            widgetRange_step           = 1,
                            widgetRange_textFormatting = "%spx",
                            key                        = Config.Key.Deadzone
                        },
                        {
                            widgetName                 = L["Config - Behavior - ProbeSize"],
                            widgetDescription          = Description(function() return BehaviorDescription(Config.Key.ProbeSize) end),
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            widgetRange_min            = 1,
                            -- The largest Distance to Select. With Select From = Cursor, it's
                            -- capped to the current one when used.
                            widgetRange_max            = Config.DEADZONE_MAX,
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
                            widgetDescription        = Description(L["Config - Display - OpenAt - Description"]),
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.OpenAt's order (Config.lua)
                                L["Config - Display - OpenAt - Cursor"],
                                L["Config - Display - OpenAt - Fixed"]
                            },
                            key                      = Config.Key.DisplayOpenAt
                        },
                        {
                            widgetName               = L["Config - Display - SelectFrom"],
                            widgetDescription        = Description(L["Config - Display - SelectFrom - Description"]),
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.SelectFrom's order (Config.lua)
                                L["Config - Display - SelectFrom - Cursor"],
                                L["Config - Display - SelectFrom - Menu"]
                            },
                            key                      = Config.Key.SelectFrom,
                            -- The right stick picks by its own direction, wherever the menu is.
                            showWhen                 = function() return IsFixed() and IsMouse() end
                        },
                        Button("Config - Display - EditMode", function() Menu_Display.OpenEditMode() end, IsFixed),
                        Button("Config - Display - ResetPosition", function() Menu_Display.ResetPosition() end, IsFixed)
                    }
                },
                {
                    widgetName = L["Config - Display - Appearance"],
                    widgetType = Setting_Enum.WidgetType.Container,
                    children   = {
                        {
                            widgetName                 = L["Config - Display - Scale"],
                            widgetType                 = Setting_Enum.WidgetType.Range,
                            -- The same range as the Edit Mode slider (Menu_Display).
                            widgetRange_min            = function() return Menu_Display.SCALE_MIN end,
                            widgetRange_max            = function() return Menu_Display.SCALE_MAX end,
                            widgetRange_step           = function() return Menu_Display.SCALE_STEP end,
                            widgetRange_textFormatting = "%s%%",
                            key                        = Config.Key.DisplayScale
                        },
                        CheckButton("Config - Display - ActionNames", Config.Key.ShowActionNames),
                        CheckButton("Config - Display - ActionTooltips", Config.Key.ShowActionTooltips),
                        -- Not with Select From = Menu Center, where you point at the menu itself.
                        -- Nor with a controller, since there's no mouse gesture to outline.
                        CheckButton("Config - Display - CursorGuide", Config.Key.CursorGuide,
                            function() return UsesCursorGuide() and IsMouse() end),
                        {
                            widgetName        = L["Config - Display - CursorGuideColor"],
                            widgetDescription = Description(L["Config - Display - CursorGuideColor - Description"]),
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
                            widgetDescription        = Description(function()
                                -- The chosen option's own description ("Config - Behavior -
                                -- WorldMarkerPlacement - Description - Mouse" or "- Click").
                                local click = Config.Get(Config.Key.WorldMarkerPlacement) == env.Enum.WorldMarkerPlacement.Click
                                return L["Config - Behavior - WorldMarkerPlacement - Description - " .. (click and "Click" or "Mouse")]
                            end),
                            widgetType               = Setting_Enum.WidgetType.SelectionMenu,
                            widgetSelectionMenu_data = { -- in env.Enum.WorldMarkerPlacement's order (Config.lua)
                                L["Config - Behavior - WorldMarkerPlacement - Mouse"],
                                L["Config - Behavior - WorldMarkerPlacement - Click"]
                            },
                            key                      = Config.Key.WorldMarkerPlacement,
                            -- With a controller, world markers are always placed with the reticle
                            -- (Kinds\WorldMarker.lua), since there's no mouse to place them under.
                            showWhen                 = IsMouse
                        },
                        {
                            widgetName               = L["Config - Behavior - TargetMarkerUnit"],
                            widgetDescription        = Description(function()
                                -- The chosen option's own description (the Cursor ones say their
                                -- limits, in yellow). With a controller, the cursor is the reticle.
                                -- That's "Config - Behavior - TargetMarkerUnit - Description -
                                -- Target", "- Cursor" or "- CursorFocus", and the last two's
                                -- " - Controller" forms.
                                local value = Config.Get(Config.Key.TargetMarkerUnit)
                                local suffix = IsController() and " - Controller" or ""
                                for name, enumValue in pairs(env.Enum.TargetMarkerUnit) do
                                    if enumValue == value and name ~= "Target" then
                                        return L["Config - Behavior - TargetMarkerUnit - Description - " .. name .. suffix]
                                    end
                                end
                                return L["Config - Behavior - TargetMarkerUnit - Description - Target"]
                            end),
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
                            widgetName        = L["Config - General - Other - Reset - title"],
                            widgetType        = Setting_Enum.WidgetType.Button,
                            widgetButton_text = L["Config - General - Other - ResetButton"],
                            widgetDescription = Description(L["Config - General - Other - Reset - Description"]),
                            set               = function() SETTING_PROMPT:Open(RESET_SETTING_PROMPT_INFO) end
                        }
                    }
                }
            }
        },
        {
            widgetName = L["Config - Menus"],
            widgetType = Setting_Enum.WidgetType.Tab,
            children   = {
                {
                    widgetType         = Setting_Enum.WidgetType.Custom,
                    widgetCustom_build = function(parent, tab) return Menus_Tab.Build(parent, tab) end
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
                AboutGroup("Config - About - Inspirations", {
                    Credit("Config - About - Inspirations - WaypointUI"),
                    Credit("Config - About - Inspirations - Opie"),
                    -- Its technique keeps the right stick off the camera (Menu_Stick.lua). It's
                    -- also credited in README and NOTICE.
                    Credit("Config - About - Inspirations - ConsolePort"),
                }),
                -- The credit the CC BY 3.0 licence asks for (also in README, NOTICE and
                -- Art\Symbols\CREDITS.md).
                AboutGroup("Config - About - Artwork", {
                    Credit("Config - About - Artwork - Symbols")
                }),
                AboutGroup("Config - About - Developer", {
                    Credit("Config - About - Developer - Name")
                })
            }
        }
    }
end
