local env = select(2, ...)
local Utils_General = env.AX_Modules:New("ax_modules\\utils\\general")

local GetCursorPosition = GetCursorPosition
local byte, sub = string.byte, string.sub

function Utils_General.GetMouseDelta(originX, originY)
    local mouseX, mouseY = GetCursorPosition()
    local deltaX = mouseX - originX
    local deltaY = originY - mouseY
    return deltaX, deltaY
end

--- `text` cut to at most `maxBytes` bytes without splitting a UTF-8 character.
local function TruncateUTF8(text, maxBytes)
    if #text <= maxBytes then return text end
    local cut = maxBytes
    -- Step back over continuation bytes (10xxxxxx) so the cut lands before a character.
    while cut > 0 and (byte(text, cut + 1) or 0) >= 0x80 and (byte(text, cut + 1) or 0) < 0xC0 do
        cut = cut - 1
    end
    return sub(text, 1, cut)
end

--- A name nothing else uses: `name` itself if it's free, else "name (2)", "name (3)", ...
--- @param name string
--- @param isTaken fun(candidate: string): boolean
--- @param maxLength number|nil longest allowed name in bytes (e.g. 16 for macros); the base
---     name is shortened so the " (N)" still fits
--- @return string
function Utils_General.GetUniqueName(name, isTaken, maxLength)
    if maxLength then name = TruncateUTF8(name, maxLength) end
    if not isTaken(name) then return name end
    local number = 2
    while true do
        local suffix = " (" .. number .. ")"
        local base = maxLength and TruncateUTF8(name, maxLength - #suffix) or name
        local candidate = base .. suffix
        if not isTaken(candidate) then return candidate end
        number = number + 1
    end
end
