local env = select(2, ...)
local Path = env.AX_Modules:Import("ax_modules\\path")
local UIKit = env.AX_Modules:Import("ax_modules\\ui-kit")
local Setting_Options = env.AX_Modules:Import("@\\Setting\\Options")
local Setting_Preload = env.AX_Modules:New("@\\Setting\\Preload")

local ATLAS_TAB_BUTTON = UIKit.Define.Texture_Atlas{ path = Setting_Options.Path .. "\\Art\\Setting\\TabButton.png", inset = 128 }
-- Corners only as big as the border and bevel (48px of art), drawn at a fixed scale that matches
-- the tab buttons' on-screen border, so the game never has to shrink them to fit.
local ATLAS_SPLIT_BUTTON = UIKit.Define.Texture_Atlas{ path = Setting_Options.Path .. "\\Art\\Setting\\SplitButton.png", inset = 48 }
local ATLAS_CONTAINER =UIKit.Define.Texture_Atlas{ path = Path.Skinned(Setting_Options.Path .. "\\Art\\Setting", "WidgetContainer.png"), inset = 70, sliceMode = Enum.UITextureSliceMode.Stretched }
Setting_Preload.UIDef = {
    Divider                         = UIKit.Define.Texture{ path = Setting_Options.Path .. "\\Art\\Shape\\Square.png" },

    --Tab Button
    UITabButton                     = ATLAS_TAB_BUTTON{ left = 0 / 768, top = 0 / 512, right = 256 / 768, bottom = 256 / 512, scale = 0.575 },
    UITabButton_Highlighted         = ATLAS_TAB_BUTTON{ left = 256 / 768, top = 0 / 512, right = 512 / 768, bottom = 256 / 512, scale = 0.575 },
    UITabButton_Pushed              = ATLAS_TAB_BUTTON{ left = 512 / 768, top = 0 / 512, right = 768 / 768, bottom = 256 / 512, scale = 0.575 },
    UITabButtonSelected             = ATLAS_TAB_BUTTON{ left = 0 / 768, top = 256 / 512, right = 256 / 768, bottom = 512 / 512, scale = 0.575 },
    UITabButtonSelected_Highlighted = ATLAS_TAB_BUTTON{ left = 256 / 768, top = 256 / 512, right = 512 / 768, bottom = 512 / 512, scale = 0.575 },
    UITabButtonSelected_Pushed      = ATLAS_TAB_BUTTON{ left = 512 / 768, top = 256 / 512, right = 768 / 768, bottom = 512 / 512, scale = 0.575 },

    --Split Button (parts of one button: the tab button cut straight on the inner side; selected
    --parts gold, the others blank like an unselected tab, a faint fill while hovered / pressed)
    UISplitButton                   = (function()
        -- SplitButton.png (1024x2048, 256px cells) rows: selected left, middle, right, then plain
        -- left, middle, right; columns: normal, highlighted, pushed. Each part sits at its cell's
        -- top left: 218px tall, left and right 236px wide (one rounded end), middle 256px.
        local function Cell(row, col, width)
            return ATLAS_SPLIT_BUTTON{ left = col * 256 / 1024, top = row * 256 / 2048, right = (col * 256 + width) / 1024, bottom = (row * 256 + 218) / 2048, scale = 0.16 }
        end
        local function Part(selectedRow, plainRow, width)
            return {
                Normal = Cell(plainRow, 0, width), Highlighted = Cell(plainRow, 1, width), Pushed = Cell(plainRow, 2, width),
                Selected = Cell(selectedRow, 0, width), Selected_Highlighted = Cell(selectedRow, 1, width), Selected_Pushed = Cell(selectedRow, 2, width),
            }
        end
        return { Left = Part(0, 3, 236), Middle = Part(1, 4, 256), Right = Part(2, 5, 236) }
    end)(),

    --Container
    UICContainer                    = ATLAS_CONTAINER{ left = 0 / 512, right = 256 / 512, top = 0 / 512, bottom = 256 / 512, scale = 0.25 },
    UICSubcontainer                 = ATLAS_CONTAINER{ left = 256 / 512, right = 512 / 512, top = 0 / 512, bottom = 256 / 512, scale = 0.25 },

    --Widget
    UIWidget                        = UIKit.Define.Texture_NineSlice{ path = Setting_Options.Path .. "\\Art\\Setting\\WidgetBackground.png", inset = 70, scale = 0.125, sliceMode = Enum.UITextureSliceMode.Stretched }
}

Setting_Preload.NAME = Setting_Options.title
Setting_Preload.FRAME_NAME = Setting_Options.prefix .. "_SettingFrame"
Setting_Preload.WINDOW_NAME = Setting_Options.prefix .. "_SettingWindow"
