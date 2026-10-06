--[[
    Slice icons: the retail action button look (masked icon, border) with cooldown swipes. Used
    for the wheel's slices and center, and by the settings preview's drag icon.
]]

local env = select(2, ...)
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Layout = env.AX_Modules:Import("@\\Ring\\Layout")
local Private = env.AX_Modules:Import("@\\Ring\\Layout\\Private")

local GetAtlasInfo = C_Texture.GetAtlasInfo

-- Retail action button look (ActionButtonTemplate: 45x45 button, 46x45 frame art)
local ATLAS_ICON_BORDER = "UI-HUD-ActionBar-IconFrame"
local ATLAS_ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local ACTION_BUTTON_SIZE = 45
local ICON_BORDER_WIDTH_RATIO = 46 / ACTION_BUTTON_SIZE
local COOLDOWN_INSET_RATIO = 1 / ACTION_BUTTON_SIZE
Private.COOLDOWN_EVENTS = { -- the wheel refreshes its cooldowns and counts on these
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }


-- Action button icon

local ATLAS_PREFIX = "atlas:"

--- Shows an action's icon on `texture`: an icon file / id, or an atlas written "atlas:<name>"
--- (kinds may return either, see Ring_Actions.GetIcon). Clears the atlas's texture coordinates
--- when going back to a file, so the next icon isn't cropped.
function Ring_Layout.SetIcon(texture, icon)
    if type(icon) == "string" and icon:sub(1, #ATLAS_PREFIX) == ATLAS_PREFIX then
        texture:SetAtlas(icon:sub(#ATLAS_PREFIX + 1))
    else
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetTexture(icon)
    end
end

--- Icon with the retail action bar mask and border, in its own frame so both scale together.
--- `.Icon` is the texture to set.
function Ring_Layout.CreateActionIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetUsingParentLevel(true)
    frame:SetSize(size, size)

    frame.Icon = frame:CreateTexture(nil, "OVERLAY", nil, 3)
    frame.Icon:SetAllPoints()

    -- ActionButtonTemplate leaves IconMask at its native atlas size, centered on the 45px icon
    -- (the mask art is larger than the icon). Keep that ratio at our icon size.
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAtlas(ATLAS_ICON_MASK, false)
    local maskInfo = GetAtlasInfo(ATLAS_ICON_MASK)
    local maskScale = size / ACTION_BUTTON_SIZE
    if maskInfo then
        mask:SetSize(maskInfo.width * maskScale, maskInfo.height * maskScale)
    else
        mask:SetSize(size * 1.5, size * 1.5)
    end
    mask:SetPoint("CENTER", frame.Icon)
    frame.Icon:AddMaskTexture(mask)

    frame.Border = frame:CreateTexture(nil, "OVERLAY", nil, 4)
    frame.Border:SetAtlas(ATLAS_ICON_BORDER)
    frame.Border:SetSize(size * ICON_BORDER_WIDTH_RATIO, size)
    frame.Border:SetPoint("TOPLEFT")

    -- Cooldown swipe, inset so it stays inside the border, plus the charge recharge edge
    -- (like ActionButtonTemplate / LibActionButton's charge cooldown).
    local inset = size * COOLDOWN_INSET_RATIO
    frame.Cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.Cooldown:SetPoint("TOPLEFT", inset, -inset)
    frame.Cooldown:SetPoint("BOTTOMRIGHT", -inset, inset)
    frame.Cooldown:SetDrawBling(false)

    -- Recharge of a charge spell with charges left: no swipe (the spell is usable), just the
    -- moving edge, like Blizzard's action bars.
    frame.ChargeCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.ChargeCooldown:SetAllPoints(frame.Cooldown)
    frame.ChargeCooldown:SetDrawSwipe(false)
    frame.ChargeCooldown:SetDrawEdge(true)
    frame.ChargeCooldown:SetDrawBling(false)
    frame.ChargeCooldown:SetHideCountdownNumbers(true)

    -- Charges left, bottom right (like the action bars' count), above the cooldowns.
    local countLayer = CreateFrame("Frame", nil, frame)
    countLayer:SetAllPoints()
    countLayer:SetFrameLevel(frame.ChargeCooldown:GetFrameLevel() + 2)
    frame.Count = countLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.Count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    return frame
end

local function SetCooldownFromDuration(cooldown, isActive, durationObject)
    if isActive and durationObject then
        cooldown:SetCooldownFromDurationObject(durationObject)
    else
        cooldown:Clear()
    end
end

local issecretvalue = issecretvalue or function() return false end
local GetSpellDisplayCount = C_Spell.GetSpellDisplayCount

--- The count Blizzard's action bars show on a spell (charges left, cast counts). In combat the
--- numbers are secret: GetSpellDisplayCount's text can still be shown (never compared), so it's
--- used when the client has it; the fallback reads the charges and shows nothing while secret.
local function SetSpellCount(icon, spell, charges)
    if GetSpellDisplayCount then
        icon.Count:SetText(GetSpellDisplayCount(spell))
        return
    end
    local text
    if charges and not issecretvalue(charges.maxCharges) and not issecretvalue(charges.currentCharges)
        and (charges.maxCharges or 0) > 1 then
        text = charges.currentCharges
    end
    icon.Count:SetText(text)
end

--- How many of an item you have (charges included), like the action bars: only for consumable
--- or stacking items (potions, food), not for one-offs such as the Hearthstone.
local function SetItemCount(icon, itemID)
    local maxStack = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
    local counts = (C_Item.IsConsumableItem and C_Item.IsConsumableItem(itemID)) or (maxStack and maxStack > 1)
    icon.Count:SetText(counts and C_Item.GetItemCount(itemID, false, true) or nil)
end

--- Shows `slice`'s cooldown (and charge recharge) on an action icon; clears it for slices without
--- one. Spells use 12.0 duration objects, which stay usable in combat.
function Ring_Layout.UpdateIconCooldown(icon, slice)
    local kind, id = nil, nil
    if slice then kind, id = Ring_Actions.GetCooldownSource(slice) end

    if kind == "spell" and id then
        local info = C_Spell.GetSpellCooldown(id)
        local charges = C_Spell.GetSpellCharges(id)
        SetCooldownFromDuration(icon.Cooldown, info and info.isActive, C_Spell.GetSpellCooldownDuration(id))
        SetCooldownFromDuration(icon.ChargeCooldown, charges and charges.isActive, C_Spell.GetSpellChargeDuration(id))
        SetSpellCount(icon, id, charges)
    elseif kind == "item" and id then
        local start, duration, enable = C_Container.GetItemCooldown(id)
        CooldownFrame_Set(icon.Cooldown, start or 0, duration or 0, enable, false)
        icon.ChargeCooldown:Clear()
        SetItemCount(icon, id)
    elseif kind == "inventory" and id then
        local start, duration, enable = GetInventoryItemCooldown("player", id)
        CooldownFrame_Set(icon.Cooldown, start or 0, duration or 0, enable, false)
        icon.ChargeCooldown:Clear()
        icon.Count:SetText(nil)
    else
        icon.Cooldown:Clear()
        icon.ChargeCooldown:Clear()
        icon.Count:SetText(nil)
    end
end
