--[[
    The center became a slot holding its own action. A menu's quickAction used to also be an
    index into its actions (that action fired on a tap), or "last" (the last used action fired).
        - An index gives the center a copy of that action, which stays on the wheel, so the menu
          works as before. The center stays empty when the action is gone or can't be a quick
          action.
        - "last" puts a Last Used action in the center.
    It runs after 000_SavedNames, so it reads today's names, and that left these two values as
    they were.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Kinds = env.AX_Modules:Import("@\\Menu\\Kinds")

local function Run(stored)
    if type(stored.Menus) ~= "table" then return end
    for _, menu in pairs(stored.Menus) do
        if type(menu) == "table" then
            if type(menu.quickAction) == "number" then
                local action = type(menu.actions) == "table" and menu.actions[menu.quickAction]
                if type(action) == "table" and Menu_Data.CanBeQuickAction(action) then
                    menu.quickAction = CopyTable(action)
                else
                    menu.quickAction = nil
                end
            elseif menu.quickAction == "last" then
                menu.quickAction = { kind = Menu_Kinds.Kind.LastUsed }
            end
        end
    end
end

-- Menus are saved both account-wide and per character.
Private.RegisterMigration({ flag = "CenterQuickSlotAccount", db = Private.MigrationDB.Account, run = Run })
Private.RegisterMigration({ flag = "CenterQuickSlotCharacter", db = Private.MigrationDB.Character, run = Run })
