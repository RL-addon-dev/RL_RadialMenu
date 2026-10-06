--[[
    AX_Settings: an example schema that uses every widget type and every field.

    Not loaded by the library (AX_Settings.xml doesn't list it). Copy it into your addon as a
    starting point: load it after AX_Settings.xml, and point options.getSchema at it:

        getSchema = function() return env.AX_Modules:Import("@\\Setting\\Schema").SCHEMA end

    Values are read and written through options.storage by `key`. The keys below would need
    defaults in your saved variables (e.g. Scale = 100, ShowMinimap = true, Theme = 1,
    AccentColor = { r = 1, g = 0.82, b = 0 }, Nickname = "").
]]

local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Setting_Define = env.AX_Modules:Import("@\\Setting\\Define")
local Setting_Enum = env.AX_Modules:Import("@\\Setting\\Enum")
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local Setting = env.AX_Modules:Await("@\\Setting")
local Setting_Schema = env.AX_Modules:New("@\\Setting\\Schema")

local WidgetType = Setting_Enum.WidgetType
local Descriptor = Setting_Define.Descriptor

-- Your own storage, for showWhen / disableWhen and dynamic values.
local function Get(key) return env.AX_SettingsOptions.storage.get(key) end

Setting_Schema.SCHEMA = {
    ----------------------------------------------------------------------------- a normal tab
    {
        widgetName = "General",                          -- the tab button's text
        widgetType = WidgetType.Tab,
        children   = {
            -- Title: a large heading with an image (TitleInfo is required).
            {
                widgetType       = WidgetType.Title,
                widgetTitle_info = Setting_Define.TitleInfo{
                    imagePath = "Interface\\Icons\\INV_Misc_Gear_01",
                    text      = "My Addon",
                    subtext   = "Version 1.0",
                },
            },

            -- Container: a titled box grouping widgets.
            {
                widgetName = "Display",
                widgetType = WidgetType.Container,
                children   = {
                    -- Range: a slider. min / max / step are required; key is required.
                    {
                        widgetName                 = "Scale",
                        widgetDescription          = Descriptor{ description = "Size of the frame." },
                        widgetType                 = WidgetType.Range,
                        widgetRange_min            = 50,
                        widgetRange_max            = 200,
                        widgetRange_step           = 5,
                        widgetRange_textFormatting = "%s%%",      -- shown next to the slider
                        key                        = "Scale",
                        set                        = function(slider, value, userInput) end,
                    },

                    -- Range with dynamic bounds (functions; re-read on every refresh when both
                    -- min and max are functions) and a formatting function.
                    {
                        widgetName                     = "Offset",
                        widgetType                     = WidgetType.Range,
                        widgetRange_min                = function() return 0 end,
                        widgetRange_max                = function() return Get("Scale") end,
                        widgetRange_step               = function() return 1 end,
                        widgetRange_textFormattingFunc = function(value) return value .. " px" end,
                        key                            = "Offset",
                        indent                         = 1,       -- nested one level under Scale
                    },

                    -- CheckButton: a boolean.
                    {
                        widgetName        = "Show Minimap Button",
                        widgetDescription = Descriptor{
                            description = "With a small image next to the text.",
                            imagePath   = "Interface\\Icons\\INV_Misc_Map_01",
                            imageType   = Setting_Enum.ImageType.Small,   -- or .Large
                        },
                        widgetType        = WidgetType.CheckButton,
                        key               = "ShowMinimap",
                        set               = function(widget, checked) end,
                    },

                    -- SelectionMenu: a dropdown; the stored value is the index into the list.
                    {
                        widgetName               = "Theme",
                        widgetType               = WidgetType.SelectionMenu,
                        widgetSelectionMenu_data = { "Dark", "Light", "Classic" }, -- or a function returning it
                        key                      = "Theme",
                        set                      = function(menu, index) end,
                    },

                    -- ColorInput: stores { r, g, b } (0-1).
                    {
                        widgetName  = "Accent Color",
                        widgetType  = WidgetType.ColorInput,
                        key         = "AccentColor",
                        set         = function(colorInput, color) end,
                        showWhen    = function(widget) return Get("Theme") == 1 end,  -- only for Dark
                    },

                    -- Input: a text box; `set` runs while typing.
                    {
                        widgetName              = "Nickname",
                        widgetType              = WidgetType.Input,
                        widgetInput_placeholder = "Type a name",
                        key                     = "Nickname",
                        set                     = function(input, text) end,
                        disableWhen             = function(widget) return not Get("ShowMinimap") end,
                    },

                    -- Container inside a container: the sub-container look.
                    {
                        widgetName               = "Advanced",
                        widgetType               = WidgetType.Container,
                        widgetContainer_isNested = true,
                        children                 = {
                            -- Text: a line of text (name + description), no control.
                            {
                                widgetName        = "Note",
                                widgetDescription = Descriptor{ description = "Changes apply after a /reload." },
                                widgetType        = WidgetType.Text,
                            },
                        },
                    },
                },
            },

            -- Container without a box.
            {
                widgetName        = "Maintenance",
                widgetType        = WidgetType.Container,
                widgetTransparent = true,
                children          = {
                    -- Button: runs `set` when clicked; refreshOnClick re-reads every widget after.
                    {
                        widgetName                  = "Reset to default",
                        widgetDescription           = Descriptor{ description = "Resets the settings above." },
                        widgetType                  = WidgetType.Button,
                        widgetButton_text           = "Reset",
                        widgetButton_refreshOnClick = true,
                        set                         = function(button)
                            _G[Setting_Preload.FRAME_NAME].Prompt:Open({
                                text         = "Reset all settings?",
                                options      = {
                                    { text = "Reset", callback = function()
                                        -- reset your stored values here, then:
                                        CallbackRegistry.Trigger("Setting.Refresh")
                                    end },
                                    { text = "Cancel" },
                                },
                                hideOnEscape = true,
                                timeout      = 10,
                            })
                        end,
                    },
                },
            },
        },
    },

    ----------------------------------------------------------------------------- a list tab
    -- Custom widget: hand-built UI. Here it also attaches a list to the sidebar (the list tab
    -- should be the last tab above the footer).
    {
        widgetName = "Profiles",
        widgetType = WidgetType.Tab,
        children   = {
            {
                widgetType         = WidgetType.Custom,
                widgetCustom_build = function(parent, tab)
                    -- Build a UIKit frame for the page (see Setting\Setting_Widgets.lua for ready
                    -- containers and rows), parent it, and return it.
                    local page = CreateFrame("Frame", nil, parent) -- stand-in: use a UIKit frame
                    page.selectedId = "default"

                    page.Nav = Setting.AttachListNav(tab, {
                        sections = {
                            {
                                title    = "Built-In",
                                visible  = 2,
                                getItems = function()
                                    return { { id = "default", title = "Default", left = "", right = "Account" } }
                                end,
                            },
                            {
                                title     = "Your Profiles",
                                newButton = { text = "+ New Profile", onClick = function() --[[ create, then page.Nav:Select(newId) ]] end },
                                getItems  = function() return {} end,
                            },
                        },
                        getSelected = function() return page.selectedId end,
                        onSelect    = function(id) page.selectedId = id --[[ fill the page for id ]] end,
                    })

                    -- Called on every settings refresh.
                    function page:OnSettingRefresh() self.Nav:Refresh() end
                    return page
                end,
            },
        },
    },

    ----------------------------------------------------------------------------- a footer tab
    {
        widgetName         = "About",
        widgetType         = WidgetType.Tab,
        widgetTab_isFooter = true,                       -- at the bottom of the sidebar
        children           = {
            {
                widgetName = "Credits",
                widgetType = WidgetType.Container,
                children   = {
                    { widgetName = "Made with AX_Settings", widgetType = WidgetType.Text },
                },
            },
        },
    },
}
