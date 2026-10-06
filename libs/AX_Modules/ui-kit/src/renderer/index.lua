local env = select(2, ...)
local UIKit_Renderer_Cleaner = env.AX_Modules:Import("ax_modules\\ui-kit\\renderer\\cleaner")
local UIKit_Renderer_Scanner = env.AX_Modules:Import("ax_modules\\ui-kit\\renderer\\scanner")
local UIKit_Renderer = env.AX_Modules:New("ax_modules\\ui-kit\\renderer")

UIKit_Renderer.Cleaner = UIKit_Renderer_Cleaner
UIKit_Renderer.Scanner = UIKit_Renderer_Scanner
