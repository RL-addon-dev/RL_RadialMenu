local env = select(2, ...)
local Struct = env.AX_Modules:Import("ax_modules\\struct").New
local Setting_Define = env.AX_Modules:New("@\\Setting\\Define")

Setting_Define.TitleInfo = Struct{
    imagePath = nil,
    text      = nil,
    subtext   = nil
}

Setting_Define.Descriptor = Struct{
    imageType   = nil,
    imagePath   = nil,
    description = nil
}
