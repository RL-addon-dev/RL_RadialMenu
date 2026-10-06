local env = select(2, ...)
local AX_Modules = {}
env.AX_Modules = AX_Modules

function AX_Modules:New(name)
    env["ax:" .. name] = {}
    return env["ax:" .. name]
end

function AX_Modules:Import(name)
    return env["ax:" .. name]
end

local awaitMetatable = {
    __index = function(self, key)
        return env["ax:" .. rawget(self, "name")][key]
    end
}

function AX_Modules:Await(name)
    return setmetatable({ name = name }, awaitMetatable)
end
