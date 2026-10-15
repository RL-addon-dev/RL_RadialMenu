local env = select(2, ...)
local UIAnim_Engine = env.AX_Modules:Import("ax_modules\\ui-anim\\engine")
local UIAnim_Methods = env.AX_Modules:Import("ax_modules\\ui-anim\\methods")
local UIAnim_Enum = env.AX_Modules:Import("ax_modules\\ui-anim\\enum")
local UIAnim = env.AX_Modules:New("ax_modules\\ui-anim")

UIAnim.Enum = UIAnim_Enum
UIAnim.New = UIAnim_Engine.New
UIAnim.Animate = UIAnim_Engine.Animate
UIAnim.AnimateNumber = UIAnim_Methods.AnimateNumber
--- Running animations (both kinds): while any run, the engine updates every frame.
function UIAnim.GetActiveCount()
    return UIAnim_Engine.GetActiveCount() + UIAnim_Methods.GetActiveCount()
end
