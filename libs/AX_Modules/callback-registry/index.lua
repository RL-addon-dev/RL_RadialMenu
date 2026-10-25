--[[
    CallbackRegistry: named events inside the addon. Add a callback for an id, and Trigger the id
    to call them all, in priority order (lowest first, then in the order they were added).
]]

local env = select(2, ...)
local CallbackRegistry = env.AX_Modules:New("ax_modules\\callback-registry")

local tinsert = table.insert
local floor = math.floor

local db = {}

local function insertCallback(callbacks, entry)
    local low, high = 1, #callbacks

    while low <= high do
        local mid = floor((low + high) * 0.5)
        if entry.priority < callbacks[mid].priority then
            high = mid - 1
        else
            low = mid + 1
        end
    end

    tinsert(callbacks, low, entry)
end

--- Calls `func(id, ...)` whenever `id` is triggered.
---@param id string
---@param func fun(id: string, ...)
---@param priority number? lower runs first (0 by default)
function CallbackRegistry.Add(id, func, priority)
    local callbacks = db[id]
    if not callbacks then
        callbacks = {}
        db[id] = callbacks
    end

    insertCallback(callbacks, {
        func     = func,
        priority = priority or 0
    })
end

--- Calls every callback added for `id`, with `id` and the other arguments.
---@param id string
---@param ... any
function CallbackRegistry.Trigger(id, ...)
    local callbacks = db[id]
    if not callbacks then return end

    for i = 1, #callbacks do
        callbacks[i].func(id, ...)
    end
end
