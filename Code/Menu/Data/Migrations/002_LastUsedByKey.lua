--[[
    Last Used is saved by action identity (Menu_Data.GetActionKey), not position. Older saves held
    the index of the action last used in each menu. It becomes that action's key, or is dropped
    when the action is gone. It runs after 000_SavedNames, so it reads today's names.
]]

local env = select(2, ...)
local Menu_Data = env.AX_Modules:Import("@\\Menu\\Data")
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")

Private.RegisterMigration({
    flag = "LastUsedByKey",
    db   = Private.MigrationDB.Character,
    run  = function(stored)
        local lastUsed = stored.LastUsedAction
        if type(lastUsed) ~= "table" then return end
        for id, value in pairs(lastUsed) do
            if type(value) == "number" then
                local menu = Menu_Data.GetMenu(id)
                local action = menu and type(menu.actions) == "table" and menu.actions[value]
                lastUsed[id] = type(action) == "table" and Menu_Data.GetActionKey(action) or nil
            end
        end
    end,
})
