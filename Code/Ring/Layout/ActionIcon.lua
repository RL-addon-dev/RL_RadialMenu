--[[
    Ring_Layout: action icons, with the Retail action button look (a masked icon and a border),
    cooldown swipes, counts and states. The wheel's wedges and center use them, and so does the
    settings preview's drag icon.
]]

local env = select(2, ...)
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Kinds = env.AX_Modules:Import("@\\Ring\\Kinds")
local Ring_Layout = env.AX_Modules:Import("@\\Ring\\Layout")
local Private = env.AX_Modules:Import("@\\Ring\\Layout\\Private")

local GetAtlasInfo = C_Texture.GetAtlasInfo

-- The Retail action button look (ActionButtonTemplate, a 45x45 button with 46x45 frame art).
local ATLAS_ICON_BORDER  = "UI-HUD-ActionBar-IconFrame"
local ATLAS_ICON_MASK    = "UI-HUD-ActionBar-IconFrame-Mask"
local ATLAS_ICON_CHECKED = "UI-HUD-ActionBar-IconFrame-Mouseover" -- ActionButtonTemplate's CheckedTexture
local CHECKED_FALLBACK   = "Interface\\Buttons\\CheckButtonHilight"
local ATLAS_OUT_OF_RANGE = "UI-CooldownManager-OORshadow" -- the Cooldown Manager's out of range shade
local OUT_OF_RANGE_ALPHA = 0.5
local ACTION_BUTTON_SIZE = 45
local ICON_BORDER_WIDTH_RATIO = 46 / ACTION_BUTTON_SIZE
local COOLDOWN_INSET_RATIO = 1 / ACTION_BUTTON_SIZE
local MASK_FALLBACK_SCALE = 1.5 -- the mask's size for the icon's, when its atlas is missing
-- A kind's underlay (world markers' beam) around the icon, kept clear of its neighbors.
local UNDERLAY_SCALE = 1.75
local COUNT_INSET = 2 -- the count's offset from the bottom-right corner, like the action bars'
-- The wheel refreshes its cooldowns and counts on these.
Private.COOLDOWN_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
}

--- An icon texture that may hold an addon symbol's tint (Ring_Layout.SetIcon).
---@class TintedTexture : Texture
---@field symbolTint number[]?

--- An action icon (Ring_Layout.CreateActionIcon).
---@class ActionIcon : Frame
---@field Icon TintedTexture the icon to set (Ring_Layout.SetIcon)
---@field Underlay Texture a kind's art behind the icon
---@field OutOfRange Texture? the out of range shade, on clients with its art
---@field Border Texture
---@field Checked Texture the active stance or form frame
---@field Cooldown Cooldown
---@field ChargeCooldown Cooldown the recharge edge of a spell with charges left
---@field Count FontString charges or item count
---@field procGlowing boolean? its proc glow is shown (UpdateIconState)


-- Action button icon

local ATLAS_PREFIX = "atlas:"
local WHITE = { 1, 1, 1 } -- an icon's own colors (no tint)

--- Shows an action's icon on `texture`. It's an icon file or id, or an atlas written
--- "atlas:<name>" (kinds may return either, see Ring_Actions.GetIcon). Going back to a file clears
--- the atlas's texture coordinates, so the next icon isn't cropped. The addon's symbols
--- (Ring_Kinds.GetSymbol) are tinted, and texture.symbolTint keeps the tint for UpdateIconState.
---@param texture TintedTexture
---@param icon number|string|nil
function Ring_Layout.SetIcon(texture, icon)
    if type(icon) == "string" and icon:sub(1, #ATLAS_PREFIX) == ATLAS_PREFIX then
        texture:SetAtlas(icon:sub(#ATLAS_PREFIX + 1))
    else
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetTexture(icon)
    end
    texture.symbolTint = Ring_Kinds.IsSymbol(icon) and Ring_Kinds.SYMBOL_COLOR or nil
    local tint = texture.symbolTint or WHITE
    texture:SetVertexColor(tint[1], tint[2], tint[3])
end

--- Shows `slice` on an action icon: its icon, and the action button border unless its kind has
--- none (noIconBorder, for markers and emotes, which show their art on its own).
---@param iconFrame ActionIcon
---@param slice Slice?
function Ring_Layout.SetSliceIcon(iconFrame, slice)
    Ring_Layout.SetIcon(iconFrame.Icon, slice and Ring_Actions.GetIcon(slice) or Ring_Kinds.QUESTION_MARK_ICON)
    iconFrame.Border:SetShown(not (slice and Ring_Actions.HasNoIconBorder(slice)))
    Ring_Layout.SetUnderlay(iconFrame, slice)
end

--- Shows what `slice`'s kind draws behind its icon (a world marker's beam of light), or nothing.
---@param iconFrame ActionIcon
---@param slice Slice?
function Ring_Layout.SetUnderlay(iconFrame, slice)
    local texture, color = nil, nil
    if slice then texture, color = Ring_Actions.GetUnderlay(slice) end
    if texture then
        iconFrame.Underlay:SetTexture(texture)
        iconFrame.Underlay:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1)
    end
    iconFrame.Underlay:SetShown(texture ~= nil)
end

--- An icon with the Retail action bar mask and border, in its own frame so both scale together.
---@param parent Frame
---@param size number
---@return ActionIcon
function Ring_Layout.CreateActionIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent) --[[@as ActionIcon]]
    frame:SetUsingParentLevel(true)
    frame:SetSize(size, size)

    frame.Icon = frame:CreateTexture(nil, "OVERLAY", nil, 3) --[[@as TintedTexture]]
    frame.Icon:SetAllPoints()

    -- A kind's underlay (SetUnderlay), behind the icon, a little larger and unmasked.
    frame.Underlay = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.Underlay:SetSize(size * UNDERLAY_SCALE, size * UNDERLAY_SCALE)
    frame.Underlay:SetPoint("CENTER", frame.Icon)
    frame.Underlay:Hide()

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
        mask:SetSize(size * MASK_FALLBACK_SCALE, size * MASK_FALLBACK_SCALE)
    end
    mask:SetPoint("CENTER", frame.Icon)
    frame.Icon:AddMaskTexture(mask)

    -- Out of range, a shadow over the icon besides its red tint, like the Cooldown Manager
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

    -- The action bars' checked frame, for an active stance, form or current spell (UpdateIconState).
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

    -- The cooldown swipe, inset so it stays inside the border, plus the charge recharge edge (like
    -- ActionButtonTemplate and LibActionButton's charge cooldown).
    local inset = size * COOLDOWN_INSET_RATIO
    frame.Cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate") --[[@as Cooldown]]
    frame.Cooldown:SetPoint("TOPLEFT", inset, -inset)
    frame.Cooldown:SetPoint("BOTTOMRIGHT", -inset, inset)
    frame.Cooldown:SetDrawBling(false)

    -- The recharge of a spell with charges left shows no swipe (the spell is usable), just the
    -- moving edge, like Blizzard's action bars.
    frame.ChargeCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate") --[[@as Cooldown]]
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
    frame.Count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -COUNT_INSET, COUNT_INSET)

    return frame
end

--- Shows a duration object's cooldown on `cooldown`, or clears it.
---@param cooldown Cooldown
---@param isActive boolean?
---@param durationObject table?
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
--- numbers are secret. GetSpellDisplayCount's text can still be shown (it's never compared), so
--- it's used when the client has it. The fallback reads the charges, and shows nothing while
--- they're secret.
---@param icon ActionIcon
---@param spell number|string
---@param charges table?
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

--- How many of an item you have (charges included), like the action bars. It's only shown for
--- consumable or stacking items (potions, food), not for one-offs such as the Hearthstone.
---@param icon ActionIcon
---@param itemID number
local function SetItemCount(icon, itemID)
    local maxStack = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
    local counts = (C_Item.IsConsumableItem and C_Item.IsConsumableItem(itemID)) or (maxStack and maxStack > 1)
    -- SetText takes numbers too.
    icon.Count:SetText(counts and C_Item.GetItemCount(itemID, false, true) or nil --[[@as string?]])
end

--- Shows `slice`'s cooldown (and charge recharge) on an action icon, or clears it for actions
--- without one. Spells use 12.0 duration objects, which stay usable in combat.
---@param icon ActionIcon
---@param slice Slice?
function Ring_Layout.UpdateIconCooldown(icon, slice)
    local source, id = nil, nil
    if slice then source, id = Ring_Actions.GetCooldownSource(slice) end

    if source == Ring_Kinds.Source.Spell and id then
        -- 12.0's isActive isn't in the editor's annotations yet.
        local info = C_Spell.GetSpellCooldown(id) --[[@as table?]]
        local charges = C_Spell.GetSpellCharges(id) --[[@as table?]]
        SetCooldownFromDuration(icon.Cooldown, info and info.isActive, C_Spell.GetSpellCooldownDuration(id))
        SetCooldownFromDuration(icon.ChargeCooldown, charges and charges.isActive, C_Spell.GetSpellChargeDuration(id))
        SetSpellCount(icon, id, charges)
    elseif source == Ring_Kinds.Source.Item and id then
        local start, duration, enable = C_Container.GetItemCooldown(id)
        CooldownFrame_Set(icon.Cooldown, start or 0, duration or 0, enable, false)
        icon.ChargeCooldown:Clear()
        SetItemCount(icon, id)
    elseif source == Ring_Kinds.Source.Inventory and id then
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



-- Icon states (in-game menu), with Blizzard's action button colors and checked frame

local IsSpellUsable, IsSpellInRange, IsCurrentSpell = C_Spell.IsSpellUsable, C_Spell.IsSpellInRange, C_Spell.IsCurrentSpell
local IsUsableItem = C_Item.IsUsableItem
local IsSpellOverlayed = C_SpellActivationOverlay.IsSpellOverlayed

-- The Cooldown Manager's colors (CooldownViewerConstants), the same as the action bars' blue and grey.
local COLOR_OUT_OF_RANGE = { 0.64, 0.15, 0.15 }
local COLOR_NO_RESOURCES = { 0.5, 0.5, 1.0 }
local COLOR_UNUSABLE = { 0.4, 0.4, 0.4 }

--- `value`, or nil while it's secret (12.0 combat), so the icon just stays plain.
---@generic T
---@param value T
---@return T?
local function Plain(value)
    if issecretvalue(value) then return nil end
    return value
end

--- Whether `spell` (an id or a name) is the active stance, form or aura on the stance bar.
---@param spell number|string
---@return boolean
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

--- Whether `spell` (an id or a name) has its proc glow up, like on the action bars. That's the
--- spell itself, or what it's replaced by right now.
---@param spell number|string
---@return boolean
local function IsProcGlowing(spell)
    local spellID = spell
    if type(spell) ~= "number" then
        local info = C_Spell.GetSpellInfo(spell)
        spellID = info and info.spellID
    end
    if not spellID then return false end
    if Plain(IsSpellOverlayed(spellID --[[@as number]])) then return true end
    local override = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID) -- Classic Era lacks it
    return override and override ~= spellID and Plain(IsSpellOverlayed(override)) and true or false
end

--- Shows or hides the proc glow, Blizzard's spell alert (the action bars' and the Cooldown
--- Manager's). It's shown again from scratch each time, because the alert's loop doesn't restart
--- by itself after the menu was hidden.
---@param icon ActionIcon
---@param shown boolean?
---@param skipBirth boolean? straight to the loop, without the burst (the glow was already up when
---     the icon appeared)
local function SetProcGlow(icon, shown, skipBirth)
    ActionButtonSpellAlertManager:HideAlert(icon)
    if shown then ActionButtonSpellAlertManager:ShowAlert(icon, skipBirth) end
end

--- What a spell's icon shows right now.
---@param spell number|string
---@return boolean? usable
---@return boolean? noResources
---@return boolean? inRange nil when there's no range to show (no target, or the spell has none)
---@return boolean active
---@return boolean glowing its proc glow
local function GetSpellState(spell)
    local usable, noResources = IsSpellUsable(spell)
    local inRange
    if UnitExists("target") then
        inRange = Plain(IsSpellInRange(spell, "target"))
    end
    local active = Plain(IsCurrentSpell(spell)) or IsActiveForm(spell)
    return Plain(usable), Plain(noResources), inRange, active and true or false, IsProcGlowing(spell)
end

--- Shows whether `slice` can be used right now, like the Cooldown Manager.
---     - Red and shaded while your target is out of range.
---     - Blue without enough resources.
---     - Grey while unusable.
---     - The proc glow.
---     - The action bars' checked frame while it's your active stance or form.
--- Actions without a state source (and nil) stay plain.
---@param icon ActionIcon
---@param slice Slice?
---@param fresh boolean? the icon was just given `slice` (the menu opened, a wedge changed), so its
---     glow is set up again, without the burst
function Ring_Layout.UpdateIconState(icon, slice, fresh)
    local source, id = nil, nil
    if slice then source, id = Ring_Actions.GetStateSource(slice) end

    -- The game's answers can be nil, which counts like false.
    ---@type boolean?, boolean?, boolean?, boolean?, boolean?
    local usable, noResources, inRange, active, glowing = true, false, nil, false, false
    if source == Ring_Kinds.Source.Spell and id then
        usable, noResources, inRange, active, glowing = GetSpellState(id)
    elseif source == Ring_Kinds.Source.Item and id then
        usable, noResources = IsUsableItem(id)
    elseif source == Ring_Kinds.Source.Inventory and id then
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
    color = color or icon.Icon.symbolTint -- a symbol keeps its tint (SetIcon)
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
