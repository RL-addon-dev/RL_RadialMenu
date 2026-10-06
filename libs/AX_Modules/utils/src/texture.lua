local env = select(2, ...)
local Utils_Texture = env.AX_Modules:New("ax_modules\\utils\\texture")

local CreateFrame = CreateFrame

function Utils_Texture.Preload(texturePath)
    CreateFrame("Frame"):CreateTexture():SetTexture(texturePath)
end
