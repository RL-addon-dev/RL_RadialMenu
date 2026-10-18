--[[
    A mount, or a random favorite mount (id 0).
]]

---@class MountSlice : Slice
---@field id number the mount journal id, or 0 for a random favorite

local env = select(2, ...)
local L = env.L
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")

local RANDOM_FAVORITE = 0
local RANDOM_FAVORITE_SPELL_ID = 150544 -- only for its icon and name, it can't be cast directly
-- The mount id the cursor reports for "Summon Random Favorite Mount" (the Mount Journal's random
-- favorite button). It's saved as RANDOM_FAVORITE.
local RANDOM_FAVORITE_CURSOR_ID = 268435455

--- The mount's summon spell. Nil for the random favorite and for unknown mounts.
---@param mountID number
---@return number?
local function GetMountSpellID(mountID)
    if mountID == RANDOM_FAVORITE then return nil end
    local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
    return spellID
end

Ring_Kinds.Register({
    kind = Ring_Kinds.Kind.Mount,

    validate = function(slice)
        return type(slice.id) == "number", L["Config - Rings - Edit - Error - Mount"]
    end,

    apply = function(button, suffix, slice)
        -- Casting the mount's spell also dismounts when mounted, like an action bar mount. The
        -- random favorite (and mounts whose journal info isn't available yet) use the journal API.
        local spellID = GetMountSpellID(slice.id)
        if spellID then
            -- By name, like /cast <mount>, because casting mount spells by id does nothing.
            Ring_Kinds.SetSpell(button, suffix, C_Spell.GetSpellName(spellID) or spellID)
        else
            Ring_Kinds.SetMacroText(button, suffix, ("/run C_MountJournal.SummonByID(%d)"):format(slice.id))
        end
    end,

    icon = function(slice)
        if slice.id == RANDOM_FAVORITE then return C_Spell.GetSpellTexture(RANDOM_FAVORITE_SPELL_ID) end
        return select(3, C_MountJournal.GetMountInfoByID(slice.id))
    end,
    label = function(slice)
        if slice.id == RANDOM_FAVORITE then
            return C_Spell.GetSpellName(RANDOM_FAVORITE_SPELL_ID) or L["Config - Rings - Search - RandomMount"]
        end
        return (C_MountJournal.GetMountInfoByID(slice.id))
    end,

    tooltip = function(tooltip, slice)
        local spellID = GetMountSpellID(slice.id)
        if not spellID then return false end
        tooltip:SetMountBySpellID(spellID)
        return true
    end,

    search = {
        filter = "mount",
        events = { "NEW_MOUNT_ADDED", "MOUNT_JOURNAL_USABILITY_CHANGED" },
        scan   = function(add)
            add({ kind = Ring_Kinds.Kind.Mount, id = RANDOM_FAVORITE })
            for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
                local name, _, icon, _, _, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if isCollected and not shouldHideOnChar then
                    add({ kind = Ring_Kinds.Kind.Mount, id = mountID }, name, icon)
                end
            end
        end,
    },

    lookupId = function(id)
        if not C_MountJournal.GetMountInfoByID(id) then return nil end
        local isCollected = select(11, C_MountJournal.GetMountInfoByID(id))
        local note = (not isCollected and L["Config - Rings - Search - Note - NotCollected"]) or nil
        return { kind = Ring_Kinds.Kind.Mount, id = id }, note
    end,

    cursor = {
        mount = function(mountID)
            if mountID == RANDOM_FAVORITE_CURSOR_ID then
                return { kind = Ring_Kinds.Kind.Mount, id = RANDOM_FAVORITE }
            end
            if mountID and C_MountJournal.GetMountInfoByID(mountID) then
                return { kind = Ring_Kinds.Kind.Mount, id = mountID }
            end
        end,
    },
})
