--[[
    Specializations: the player's class's specs, their info, and the current one. Uses
    C_SpecializationInfo where the client has it, else the older global functions.
]]

local env = select(2, ...)
local Utils_Spec = env.AX_Modules:New("@\\Utils\\Spec")

local SpecInfo = C_SpecializationInfo or {}
local GetSpecialization = SpecInfo.GetSpecialization or GetSpecialization
local GetSpecializationInfo = SpecInfo.GetSpecializationInfo or GetSpecializationInfo
local GetNumSpecializations = SpecInfo.GetNumSpecializations or GetNumSpecializations

--- Calls `callback(index, specID)` for every specialization of the player's class, in the game's
--- order.
---@param callback fun(index: integer, specID: number)
function Utils_Spec.ForEachSpec(callback)
    for index = 1, (GetNumSpecializations and GetNumSpecializations()) or 0 do
        local specID = GetSpecializationInfo(index)
        if specID then callback(index, specID) end
    end
end

--- The player's spec index for spec `specID`, or nil when the class has no such spec.
---@param specID number
---@return integer?
function Utils_Spec.GetSpecIndex(specID)
    for index = 1, (GetNumSpecializations and GetNumSpecializations()) or 0 do
        if GetSpecializationInfo(index) == specID then return index end
    end
end

--- The name, description and icon of spec `specID`, for any class.
---@param specID number
---@return string? name
---@return string? description
---@return number|string|nil icon
function Utils_Spec.GetSpecInfo(specID)
    if not GetSpecializationInfoByID then return nil end
    local _, name, description, icon = GetSpecializationInfoByID(specID)
    return name, description, icon
end

--- The player's current specialization.
---@return integer? index
---@return number? specID
function Utils_Spec.GetCurrentSpec()
    local index = GetSpecialization and GetSpecialization()
    if not index then return nil end
    return index, GetSpecializationInfo(index)
end
