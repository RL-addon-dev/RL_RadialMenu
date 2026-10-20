--[[
    Utils_Text: text shown in the UI, as escape codes and colors.
]]

local env = select(2, ...)
local Utils_Text = env.AX_Modules:New("@\\Utils\\Text")

-- The gold Blizzard uses for notes and highlights (NORMAL_FONT_COLOR).
local GOLD = "|cffffd100"
local COLOR_END = "|r"

--- `text` shown as it is, not read as UI escape codes. For the player's own text, like menu,
--- macro and action names.
---@param text any
---@return string
function Utils_Text.Escape(text)
    return (tostring(text or ""):gsub("|", "||"))
end

--- `text` in gold.
---@param text string
---@return string
function Utils_Text.Gold(text)
    return GOLD .. text .. COLOR_END
end
