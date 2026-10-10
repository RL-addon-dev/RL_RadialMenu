--[[
    The center became a slot holding its own action. A ring's quickAction used to also be an
    index into its slices (that slice fired on a tap), or "last" (the last used action fired).
    Index: the center gets a copy of that slice (it stays on the wheel, so the menu works as
    before), or nothing when the slice is gone or can't be a quick action. "last": a Last Used
    action in the center.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

local function Run(stored)
    if type(stored.Rings) ~= "table" then return end
    for _, ring in pairs(stored.Rings) do
        if type(ring) == "table" then
            if type(ring.quickAction) == "number" then
                local slice = type(ring.slices) == "table" and ring.slices[ring.quickAction]
                if type(slice) == "table" and Ring_Data.CanBeQuickAction(slice) then
                    ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.Custom, CopyTable(slice)
                else
                    ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.None, nil
                end
            elseif ring.quickAction == "last" then
                ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.Custom, { kind = "lastused" }
            end
        end
    end
end

-- Rings are stored in both: account-wide and per character.
Private.RegisterMigration({ flag = "CenterQuickSlotAccount", db = "account", run = Run })
Private.RegisterMigration({ flag = "CenterQuickSlotCharacter", db = "character", run = Run })
