--[[
    Action Bar 1-8. Each holds its bar's 12 buttons (Kinds\ActionBar.lua, each hidden while it's
    empty or the bar is turned off), to add to other menus as a submenu, either scrolled, or spread
    so the buttons are on the wheel like the bar. Action Bar 1 follows its page (stance, form,
    stealth, ...).
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

--- The library menu key of Action Bar `bar` (saved data, never renamed).
---@param bar integer
---@return string
local function GetKey(bar)
    return "actionbar" .. bar
end

--- This character's Action Bar `bar` menu, or nil.
---@param bar integer 1 to 8
---@return Menu?
function Menu_Data.GetActionBarMenu(bar)
    return Menu_Data.GetLibraryMenu(GetKey(bar))
end

for bar = 1, Menu_Kinds.NUM_ACTION_BARS do
    Menu_Data.RegisterLibraryMenu({
        key      = GetKey(bar),
        category = Menu_Data.LibraryCategory.ActionBars,
        name     = "Config - Menus - ActionBarMenu - " .. bar, -- one locale string per bar
        -- Always the 12 buttons. Each hides while it's empty.
        scan     = function()
            local actions = {}
            for button = 1, Menu_Kinds.NUM_ACTION_BUTTONS do
                actions[button] = { kind = Menu_Kinds.Kind.ActionSlot, bar = bar, button = button }
            end
            return actions
        end,
    })
end
