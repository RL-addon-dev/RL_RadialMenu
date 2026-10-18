--[[
    The center became a slot holding its own action. A menu's quickAction used to also be an
    index into its slices (that action fired on a tap), or "last" (the last used action fired).
        - An index gives the center a copy of that action, which stays on the wheel, so the menu
          works as before. The center stays empty when the action is gone or can't be a quick
          action.
        - "last" puts a Last Used action in the center.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

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
                ring.quickAction, ring.quickSlice = Ring_Data.QuickAction.Custom, { kind = Ring_Kinds.Kind.LastUsed }
            end
        end
    end
end

-- Menus are saved both account-wide and per character.
Private.RegisterMigration({ flag = "CenterQuickSlotAccount", db = Private.MigrationDB.Account, run = Run })
Private.RegisterMigration({ flag = "CenterQuickSlotCharacter", db = Private.MigrationDB.Character, run = Run })
