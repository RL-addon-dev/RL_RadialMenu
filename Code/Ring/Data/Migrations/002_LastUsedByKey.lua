--[[
    Last Used is stored by slice identity (Ring_Data.GetSliceKey), not position. Older saves stored
    the index of the slice last used in each ring: it becomes that slice's key, or is dropped when
    the slice is gone.
]]

local env = select(2, ...)
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Private = env.AX_Modules:Import("@\\Ring\\Data\\Private")

Private.RegisterMigration({
    flag = "LastUsedByKey",
    db   = "character",
    run  = function(stored)
        local lastUsed = stored.LastUsedSlice
        if type(lastUsed) ~= "table" then return end
        for id, value in pairs(lastUsed) do
            if type(value) == "number" then
                local ring = Ring_Data.GetRing(id)
                local slice = ring and type(ring.slices) == "table" and ring.slices[value]
                lastUsed[id] = type(slice) == "table" and Ring_Data.GetSliceKey(slice) or nil
            end
        end
    end,
})
