--[[
    Action Bar 1-8. Each holds its bar's 12 buttons (Kinds\ActionBar.lua, each hidden while it's
    empty or the bar is turned off), to add to other menus as a submenu, either scrolled, or spread
    so the buttons are on the wheel like the bar. Action Bar 1 follows its page (stance, form,
    stealth, ...).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

--- The built-in menu key of Action Bar `bar` (saved data, never renamed).
---@param bar integer
---@return string
local function GetKey(bar)
    return "actionbar" .. bar
end

--- This character's Action Bar `bar` menu, or nil.
---@param bar integer 1 to 8
---@return Ring?
function Ring_Data.GetActionBarRing(bar)
    return Ring_Data.GetBuiltInRing(GetKey(bar))
end

for bar = 1, Ring_Kinds.NUM_ACTION_BARS do
    Ring_Data.RegisterBuiltIn({
        key      = GetKey(bar),
        category = Ring_Data.LibraryCategory.ActionBars,
        name     = "Config - Rings - ActionBarRing - " .. bar, -- one locale string per bar
        -- Always the 12 buttons. Each hides while it's empty.
        scan     = function()
            local slices = {}
            for button = 1, Ring_Kinds.NUM_ACTION_BUTTONS do
                slices[button] = { kind = Ring_Kinds.Kind.ActionSlot, bar = bar, button = button }
            end
            return slices
        end,
    })
end
