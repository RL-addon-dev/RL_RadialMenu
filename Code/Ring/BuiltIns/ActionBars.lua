--[[
    Action Bar 1-8: each holds its bar's 12 buttons (Kinds\ActionBar.lua: each hidden while it's
    empty or the bar is turned off), to add to other menus as a submenu: scrolled, or spread so
    the buttons are on the wheel like the bar. Action Bar 1 follows its page (stance, form,
    stealth, ...).
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

for bar = 1, Ring_Kinds.NUM_ACTION_BARS do
    Ring_Data.RegisterBuiltIn({
        key    = "actionbar" .. bar,
        name   = "Config - Rings - ActionBarRing - " .. bar,
        -- Always the 12 buttons; each hides while it's empty.
        scan   = function()
            local slices = {}
            for button = 1, Ring_Kinds.NUM_ACTION_BUTTONS do
                slices[button] = { kind = "actionslot", bar = bar, button = button }
            end
            return slices
        end,
    })
end
