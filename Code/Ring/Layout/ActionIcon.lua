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
local ATLAS_ICON_CHECKED = "UI-HUD-ActionBar-IconFrame-Mouseover" -- ActionButtonTemplate's CheckedTexture
local CHECKED_FALLBACK = "Interface\\Buttons\\CheckButtonHilight"
local ATLAS_OUT_OF_RANGE = "UI-CooldownManager-OORshadow" -- the Cooldown Manager's out of range shade
local OUT_OF_RANGE_ALPHA = 0.5
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

    -- Out of range: a shadow over the icon besides its red tint, like the Cooldown Manager
    -- (UpdateIconState). Clients without its art get the tint only.
    if Private.HasAtlas(ATLAS_OUT_OF_RANGE) then
        frame.OutOfRange = frame:CreateTexture(nil, "OVERLAY", nil, 4)
        frame.OutOfRange:SetAtlas(ATLAS_OUT_OF_RANGE)
        frame.OutOfRange:SetAlpha(OUT_OF_RANGE_ALPHA)
        frame.OutOfRange:SetAllPoints(frame.Icon)
        frame.OutOfRange:AddMaskTexture(mask)
        frame.OutOfRange:Hide()
    end

    frame.Border = frame:CreateTexture(nil, "OVERLAY", nil, 4)
    frame.Border:SetAtlas(ATLAS_ICON_BORDER)
    frame.Border:SetSize(size * ICON_BORDER_WIDTH_RATIO, size)
    frame.Border:SetPoint("TOPLEFT")

    -- Active stance, form or current spell: the action bars' checked frame (UpdateIconState).
    frame.Checked = frame:CreateTexture(nil, "OVERLAY", nil, 5)
    if Private.HasAtlas(ATLAS_ICON_CHECKED) then
        frame.Checked:SetAtlas(ATLAS_ICON_CHECKED)
        frame.Checked:SetSize(size * ICON_BORDER_WIDTH_RATIO, size)
        frame.Checked:SetPoint("TOPLEFT")
    else
        frame.Checked:SetTexture(CHECKED_FALLBACK)
        frame.Checked:SetBlendMode("ADD")
        frame.Checked:SetAllPoints(frame.Icon)
    end
    frame.Checked:Hide()

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



-- Icon states (in-game menu): Blizzard's action button colors and checked frame

local IsSpellUsable, IsSpellInRange, IsCurrentSpell = C_Spell.IsSpellUsable, C_Spell.IsSpellInRange, C_Spell.IsCurrentSpell
local IsUsableItem = C_Item.IsUsableItem
local IsSpellOverlayed = C_SpellActivationOverlay.IsSpellOverlayed

-- The Cooldown Manager's colors (CooldownViewerConstants), the same as the action bars' blue and grey.
local COLOR_OUT_OF_RANGE = { 0.64, 0.15, 0.15 }
local COLOR_NO_RESOURCES = { 0.5, 0.5, 1.0 }
local COLOR_UNUSABLE = { 0.4, 0.4, 0.4 }

--- A value to act on: nil while it's secret (12.0 combat), so the icon just stays plain.
local function Plain(value)
    if issecretvalue(value) then return nil end
    return value
end

--- Whether `spell` (an id or a name) is the active stance / form / aura on the stance bar.
local function IsActiveForm(spell)
    local name = type(spell) == "number" and C_Spell.GetSpellName(spell) or spell
    for i = 1, GetNumShapeshiftForms() do
        local _, active, _, formSpellID = GetShapeshiftFormInfo(i)
        if Plain(active) and formSpellID and (formSpellID == spell or C_Spell.GetSpellName(formSpellID) == name) then
            return true
        end
    end
    return false
end

--- Whether `spell` (an id or a name) has its proc glow up, like on the action bars: the spell
--- itself or what it's replaced by right now.
local function IsProcGlowing(spell)
    local spellID = spell
    if type(spell) ~= "number" then
        local info = C_Spell.GetSpellInfo(spell)
        spellID = info and info.spellID
    end
    if not spellID then return false end
    if Plain(IsSpellOverlayed(spellID)) then return true end
    local override = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID) -- not on every client (classic era lacks it)
    return override and override ~= spellID and Plain(IsSpellOverlayed(override)) and true or false
end

--- Shows or hides the proc glow: Blizzard's spell alert (the action bars' and the Cooldown
--- Manager's). `skipBirth`: straight to the loop, without the burst (the glow was already up when
--- the icon appeared). Shown again from scratch each time: the alert's loop doesn't restart by
--- itself after the menu was hidden.
local function SetProcGlow(icon, shown, skipBirth)
    ActionButtonSpellAlertManager:HideAlert(icon)
    if shown then ActionButtonSpellAlertManager:ShowAlert(icon, skipBirth) end
end

--- @return boolean|nil usable
--- @return boolean|nil noResources
--- @return boolean|nil inRange nil: no range to show (no target, or the spell has none)
--- @return boolean active
--- @return boolean glowing proc glow
local function GetSpellState(spell)
    local usable, noResources = IsSpellUsable(spell)
    local inRange
    if UnitExists("target") then
        inRange = Plain(IsSpellInRange(spell, "target"))
    end
    local active = Plain(IsCurrentSpell(spell)) or IsActiveForm(spell)
    return Plain(usable), Plain(noResources), inRange, active and true or false, IsProcGlowing(spell)
end

--- Shows whether `slice` can be used right now, like the Cooldown Manager: red and shaded while
--- your target is out of range, blue without enough resources, grey while unusable, and the proc
--- glow; plus the action bars' checked frame while it's your active stance or form. Plain for
--- slices without a state source (and nil).
--- @param fresh boolean|nil the icon was just given `slice` (the menu opened, a wedge changed):
---   its glow is set up again, without the burst
function Ring_Layout.UpdateIconState(icon, slice, fresh)
    local kind, id = nil, nil
    if slice then kind, id = Ring_Actions.GetStateSource(slice) end

    local usable, noResources, inRange, active, glowing = true, false, nil, false, false
    if kind == "spell" and id then
        usable, noResources, inRange, active, glowing = GetSpellState(id)
    elseif kind == "item" and id then
        usable, noResources = IsUsableItem(id)
    elseif kind == "inventory" and id then
        local itemID = GetInventoryItemID("player", id)
        if itemID then usable, noResources = IsUsableItem(itemID) end
    end
    usable, noResources = Plain(usable), Plain(noResources)

    local color
    if inRange == false then
        color = COLOR_OUT_OF_RANGE
    elseif usable == false then
        color = noResources and COLOR_NO_RESOURCES or COLOR_UNUSABLE
    end
    if color then
        icon.Icon:SetVertexColor(color[1], color[2], color[3])
    else
        icon.Icon:SetVertexColor(1, 1, 1)
    end
    if icon.OutOfRange then icon.OutOfRange:SetShown(inRange == false) end
    icon.Checked:SetShown(active)

    if fresh or glowing ~= (icon.procGlowing or false) then
        if glowing or icon.procGlowing then SetProcGlow(icon, glowing, fresh) end
        icon.procGlowing = glowing
    end
end
