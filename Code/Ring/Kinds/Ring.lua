--[[
    ring    ring: submenu (nested ring) id; scrolled with the mouse wheel, or spread into the parent
            menu when expand = true (both handled by Ring_Secure, not by a click action). Hidden
            while none of its own actions are shown.
]]

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Ring_Live = env.AX_Modules:Await("@\\Ring\\Live")

local ICON = "Interface\\Icons\\INV_Misc_Gear_01"

Ring_Kinds.Register({
    kind = "ring",

    validate = function(slice, parentId)
        if Ring_Data.GetRing(slice.ring) == nil then return false, "that submenu no longer exists" end
        slice.ring = tostring(slice.ring)
        slice.nest = nil
        if Ring_Data.WouldCreateCycle(tostring(parentId), slice.ring) then
            return false, "adding that submenu would create a loop"
        end
        return true
    end,

    apply = Ring_Kinds.ClearAction,

    icon = function(slice, depth)
        -- The submenu's first action, like a folder preview.
        local ring = Ring_Data.GetRing(slice.ring)
        local first = ring and ring.slices[1]
        if first and depth < 3 then return Ring_Actions.GetIcon(first, depth + 1) end
        return ICON
    end,
    label = function(slice)
        local ring = Ring_Data.GetRing(slice.ring)
        return ring and ring.name or ("ring:" .. tostring(slice.ring))
    end,

    condition = "ring",
    available = function(slice, depth) return Ring_Live.HasShownSlices(slice.ring, depth) end,

    search = {
        filter  = "ring",
        dynamic = true,
        -- Every other menu. Menus that already contain the one being edited are listed but
        -- `blocked` (adding them would nest in a loop), so the user sees why they can't be added.
        scan    = function(add, ringId)
            for _, ring in ipairs(Ring_Data.GetRings()) do
                if ring.id ~= ringId then
                    local candidate = add({ kind = "ring", ring = ring.id }, ring.name)
                    if candidate and Ring_Data.WouldCreateCycle(ringId, ring.id) then
                        candidate.blocked = L["Config - Rings - Search - Blocked - Loop"]
                    end
                end
            end
        end,
    },
})
