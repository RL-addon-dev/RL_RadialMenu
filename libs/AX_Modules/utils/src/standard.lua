local env = select(2, ...)
local Utils_Standard = env.AX_Modules:New("ax_modules\\utils\\standard")

local pairs = pairs

--- How many keys `tbl` has (not only its array part).
---@param tbl table
---@return integer
function Utils_Standard.GetTableLength(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

--- A new array with `tbl`'s array part in reverse order.
---@param tbl any[]
---@return any[]
function Utils_Standard.ReverseTable(tbl)
    local reversed = {}
    local length = #tbl
    for i = length, 1, -1 do
        reversed[length - i + 1] = tbl[i]
    end
    return reversed
end

--- Makes reading a key `tbl` doesn't have an error instead of nil, so a misspelled constant
--- (`Event.DataChaged`) fails where it's written rather than silently doing nothing.
---@generic T: table
---@param tbl T
---@param label string what the keys are, for the error ("event", "setting key")
---@return T tbl
function Utils_Standard.Strict(tbl, label)
    return setmetatable(tbl, {
        __index = function(_, key) error("unknown " .. label .. ": " .. tostring(key), 2) end,
    })
end

--- `parent[key]`, made an empty table first when it isn't one (missing, or old data of another type).
---@param parent table
---@param key any
---@return table
function Utils_Standard.GetOrCreateTable(parent, key)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    return parent[key]
end

local nextUniqueID = 0

--- A number no other call returned (this session).
---@return integer
function Utils_Standard.GetUniqueID()
    nextUniqueID = nextUniqueID + 1
    return nextUniqueID
end
