--[[
    A submenu. It's scrolled with the mouse wheel, or spread into the parent menu with `expand`
    (Ring_Secure handles both, there's no click action). It's hidden while none of its own actions
    are shown.
]]

---@class RingSlice : Slice
---@field ring string the submenu's Ring id
---@field nest nil an old field ("open" or "scroll" mode), cleared when found

local env = select(2, ...)
local L = env.L
local Ring_Data = env.AX_Modules:Import("@\\Ring\\Data")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Actions = env.AX_Modules:Await("@\\Ring\\Actions")
local Ring_Live = env.AX_Modules:Await("@\\Ring\\Live")

local ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local MAX_ICON_DEPTH = 3 -- how deep a submenu's icon looks into submenus inside it

--- The submenu, for its name and icon. That's this character's, else another class's or
--- character's. Those are shown in the settings and hidden in game, because the submenu doesn't
--- exist here and has nothing to show.
---@param id string
---@return Ring?
local function GetDisplayRing(id)
    return Ring_Data.GetRing(id) or (Ring_Data.GetElsewhereRing(id))
end

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Ring,

    ---@param slice RingSlice
    validate = function(slice, parentId)
        if Ring_Data.GetRing(slice.ring) == nil then return false, L["Config - Rings - Edit - Error - SubmenuGone"] end
        slice.ring = tostring(slice.ring)
        slice.nest = nil
        if Ring_Data.WouldCreateCycle(tostring(parentId), slice.ring) then
            return false, L["Config - Rings - Edit - Error - SubmenuLoop"]
        end
        return true
    end,

    apply = Ring_Kinds.ClearAction,

    -- The submenu's first action shown right now (else its first), like a folder preview. For an
    -- action bar, that's its first filled button.
    ---@param slice RingSlice
    icon = function(slice, depth)
        local ring = GetDisplayRing(slice.ring)
        if not ring or depth >= MAX_ICON_DEPTH then return ICON end
        for _, child in ipairs(ring.slices) do
            if Ring_Actions.IsSliceAvailable(child, depth + 1) then return Ring_Actions.GetIcon(child, depth + 1) end
        end
        return (ring.slices[1] and Ring_Actions.GetIcon(ring.slices[1], depth + 1)) or ICON
    end,
    ---@param slice RingSlice
    label = function(slice)
        local ring = GetDisplayRing(slice.ring)
        return ring and ring.name
    end,

    -- A class or character menu says whose it is, in orange like the settings' other notes.
    ---@param slice RingSlice
    tooltip = function(tooltip, slice)
        tooltip:SetText(Ring_Actions.GetLabel(slice), 1, 1, 1)
        local owner = Ring_Data.GetOwnerLabel(slice.ring)
        if owner then tooltip:AddLine(owner, 1, 0.5, 0.25, true) end
        return true
    end,

    condition = "ring",
    ---@param slice RingSlice
    available = function(slice, depth) return Ring_Live.HasShownSlices(slice.ring, depth) end,

    search = {
        filter  = "ring",
        dynamic = true,
        -- Every other menu. Menus that already contain the one being edited are listed but
        -- `blocked`, because adding them would nest in a loop, so the user sees why they can't be
        -- added.
        scan    = function(add, ringId)
            for _, ring in ipairs(Ring_Data.GetRings()) do
                if ring.id ~= ringId then
                    local candidate = add({ kind = Ring_Kinds.Kind.Ring, ring = ring.id }, ring.name)
                    if candidate and Ring_Data.WouldCreateCycle(ringId, ring.id) then
                        candidate.blocked = L["Config - Rings - Search - Blocked - Loop"]
                    end
                end
            end
        end,
    },
})
