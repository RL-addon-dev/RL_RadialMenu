--[[
    Menus' macros now all click as "Macro" (Menu_Macros), so the same macro opens its menu with a
    mouse or a controller. The crossbar's macros clicked as "Gamepad", and the oldest ones clicked
    RLRM_Ring_<id>, from before the buttons were renamed. This rewrites their bodies, keeping their
    name and icon.

    Migrations run when the saved variables load, before the macros are, and macros can't be edited
    in combat. So the rewrite waits until the player is in the world and out of combat, and the
    flag is only saved once it has run. A session that ends first tries again the next time.
]]

local env = select(2, ...)
local Private = env.AX_Modules:Import("@\\Menu\\Data\\Private")
local Menu_Macros = env.AX_Modules:Await("@\\Menu\\Macros")

local FLAG = "MenuMacroClickAccount"
-- The crossbar's old bodies, capturing the menu id.
local OLD_MACRO_PATTERNS = {
    "^#rlrm\n/click RLRM_(%d+) Gamepad",
    "^#rlrm\n/click RLRM_Ring_(%d+) Gamepad",
}

--- The menu id an old crossbar macro opens, from its body, or nil for any other macro.
---@param body string?
---@return string?
local function ParseOldBody(body)
    if not body then return nil end
    for _, pattern in ipairs(OLD_MACRO_PATTERNS) do
        local menuId = body:match(pattern)
        if menuId then return menuId end
    end
end

--- Rewrites every old crossbar macro's body. Keeping the name keeps each macro's index.
local function RewriteMacros()
    for index = 1, GetNumMacros() do
        local menuId = ParseOldBody(GetMacroBody(index))
        if menuId then
            local name, icon = GetMacroInfo(index)
            EditMacro(index, name, icon, Menu_Macros.GetBody(menuId))
        end
    end
end

--- Waits until the macros can be edited, then rewrites them and saves the flag.
---@param stored table
local function Run(stored)
    -- The runner saved the flag already. It's saved again once the macros are rewritten.
    stored[FLAG] = nil
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
    waiter:SetScript("OnEvent", function(self)
        if InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        self:UnregisterAllEvents()
        RewriteMacros()
        stored[FLAG] = true
    end)
end

Private.RegisterMigration({ flag = FLAG, db = Private.MigrationDB.Account, run = Run })
