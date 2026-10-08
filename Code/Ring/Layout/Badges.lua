--[[
    Wheel badges, on a slice's icon corner:
        scroll      mouse wheel: a submenu that scrolls (in game and preview)
        spread      stacked frames with a count: a submenu spread into this menu (preview)
        visibility  eye: the action hides when it has nothing to fire, crossed out while hidden
                    (preview; also on the center for the quick action)
    Created per wedge by Wheel.lua; shown by the WheelMixin methods at the end of this file.
]]

local env = select(2, ...)
local Ring_Actions = env.AX_Modules:Import("@\\Ring\\Actions")
local Ring_Live = env.AX_Modules:Import("@\\Ring\\Live")
local Ring_Layout = env.AX_Modules:Import("@\\Ring\\Layout")
local Private = env.AX_Modules:Import("@\\Ring\\Layout\\Private")

local HasAtlas, CLIP_MASK_TEXTURE = Private.HasAtlas, Private.FILL_TEXTURE

-- Nested ring badge: Blizzard mouse art, first one this client has. The new player tutorial's
-- middle button (wheel) icon if present, else the click-casting window's mouse icon, else a
-- small "Scroll" text pill.
local SCROLL_BADGE_ATLASES = { "newplayertutorial-icon-mouse-middlebutton", "clickcast-icon-mouse" }
local SCROLL_BADGE_SIZE = 30
local SCROLL_BADGE_X, SCROLL_BADGE_Y = -1, 1 -- center offset from the icon's bottom-right corner
-- Visibility badge (settings preview): an eye, or Blizzard's hidden (crossed-out) eye while the
-- slice is hidden. First art this client has wins; without a hidden eye, a slash is drawn over
-- the eye instead.
local CONDITION_BADGE_ATLASES = { "GM-icon-visible", "transmog-icon-visible", "socialqueuing-icon-eye" }
local CONDITION_HIDDEN_ATLASES = { "GM-icon-visibleDis", "GM-icon-hidden", "transmog-icon-hidden", "socialqueuing-icon-eye-hidden" }
local CONDITION_BADGE_TEXTURE = "Interface\\Common\\help-i"
local CONDITION_BADGE_SIZE = 56
local CONDITION_BADGE_X, CONDITION_BADGE_Y = 1, 1 -- center offset from the icon's bottom-left corner
local CONDITION_SLASH_INSET = 4 -- slash runs corner to corner, this far in
local CONDITION_SLASH_THICKNESS = 2.5
local CONDITION_SLASH_SHADOW_THICKNESS = 5
-- Expanded nested ring badge (settings preview): a small stack of square frames, like a
-- fanned hand of cards ("this is several slices"), with N (slices it adds right now) on the
-- front one. Counts above EXPAND_COUNT_MAX show as that.
local EXPAND_STACK_FRAMES = 3
local EXPAND_STACK_SIZE = 18 -- each frame
local EXPAND_STACK_STEP = 2 -- offset between frames, up and to the right
-- Grey, like the visibility eye; the back frames darker so the stack reads as layers. Each fill
-- is a top-to-bottom gradient (top, bottom) with a faint highlight line along its top edge and a
-- soft drop shadow, for the same shaded look as the mouse and eye art.
local EXPAND_FILL_BACK = { { 0.72, 0.72, 0.72 }, { 0.48, 0.48, 0.48 } }
local EXPAND_FILL_FRONT = { { 0.92, 0.92, 0.92 }, { 0.64, 0.64, 0.64 } }
local EXPAND_HIGHLIGHT = { 1, 1, 1, 0.55 }
local EXPAND_SHADOW = { 0, 0, 0, 0.45 }
local EXPAND_SHADOW_OFFSET = 1
local EXPAND_OFFSET_X, EXPAND_OFFSET_Y = -3, 1 -- badge center from the icon's bottom-right corner
local EXPAND_OUTLINE = { 0, 0, 0, 0.9 }
local EXPAND_OUTLINE_WIDTH = 1
local EXPAND_COUNT_COLOR = { 0.08, 0.08, 0.08 }
local EXPAND_COUNT_FONT = "Fonts\\FRIZQT__.TTF"
local EXPAND_COUNT_FONT_SIZE = 8
local EXPAND_COUNT_X = 0
local EXPAND_COUNT_MAX = 99
local SCROLL_PILL_WIDTH = 44
local SCROLL_PILL_HEIGHT = 14


--- The first of `names` this client has, or nil.
local function FirstAtlas(names)
    for _, name in ipairs(names) do
        if HasAtlas(name) then return name end
    end
end



-- Nested ring badge

--- Mouse icon on the icon's bottom-right corner (or a "Scroll" pill below it); child of the icon
--- so it follows the intro/outro slide and the selected scale.
function Private.CreateScrollBadge(wheel, wedge)
    local badge = CreateFrame("Frame", nil, wedge.Button)
    badge:SetFrameLevel(wheel:GetFrameLevel() + 9)

    local atlas = FirstAtlas(SCROLL_BADGE_ATLASES)
    if atlas then
        badge:SetSize(SCROLL_BADGE_SIZE, SCROLL_BADGE_SIZE)
        badge:SetPoint("CENTER", wedge.Button, "BOTTOMRIGHT", SCROLL_BADGE_X, SCROLL_BADGE_Y)
        badge.Texture = badge:CreateTexture(nil, "OVERLAY")
        badge.Texture:SetAllPoints()
        badge.Texture:SetAtlas(atlas)
    else
        badge:SetSize(SCROLL_PILL_WIDTH, SCROLL_PILL_HEIGHT)
        badge:SetPoint("TOP", wedge.Button, "BOTTOM", 0, 4)
        badge.Background = badge:CreateTexture(nil, "BACKGROUND")
        badge.Background:SetAllPoints()
        badge.Background:SetColorTexture(0, 0, 0, 0.8)
        badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge.Text:SetPoint("CENTER")
        badge.Text:SetText(env.L["Config - Rings - Nest - Badge"])
    end

    badge:Hide()
    wedge.ScrollBadge = badge

    -- Same spot, for nested rings that spread their slices into this ring instead: stacked frames,
    -- the back one first so the front one draws on top.
    local span = EXPAND_STACK_SIZE + (EXPAND_STACK_FRAMES - 1) * EXPAND_STACK_STEP
    local expand = CreateFrame("Frame", nil, wedge.Button)
    expand:SetFrameLevel(wheel:GetFrameLevel() + 9)
    expand:SetSize(span, span)
    expand:SetPoint("CENTER", wedge.Button, "BOTTOMRIGHT", EXPAND_OFFSET_X, EXPAND_OFFSET_Y)
    for i = EXPAND_STACK_FRAMES, 1, -1 do
        local offset = (i - 1) * EXPAND_STACK_STEP
        -- One draw layer, back frame lowest: each frame covers the frames behind it. Per frame:
        -- shadow, outline, fill, highlight.
        local subLevel = -8 + (EXPAND_STACK_FRAMES - i) * 4

        local shadow = expand:CreateTexture(nil, "OVERLAY", nil, subLevel)
        shadow:SetSize(EXPAND_STACK_SIZE, EXPAND_STACK_SIZE)
        shadow:SetPoint("BOTTOMLEFT", expand, "BOTTOMLEFT", offset + EXPAND_SHADOW_OFFSET, offset - EXPAND_SHADOW_OFFSET)
        shadow:SetColorTexture(unpack(EXPAND_SHADOW))

        -- Plain squares (no rounded frame art, which left edge artifacts at this size): a dark
        -- outline with the fill inset by it.
        local outline = expand:CreateTexture(nil, "OVERLAY", nil, subLevel + 1)
        outline:SetSize(EXPAND_STACK_SIZE, EXPAND_STACK_SIZE)
        outline:SetPoint("BOTTOMLEFT", expand, "BOTTOMLEFT", offset, offset)
        outline:SetColorTexture(unpack(EXPAND_OUTLINE))

        local colors = i == 1 and EXPAND_FILL_FRONT or EXPAND_FILL_BACK
        local fill = expand:CreateTexture(nil, "OVERLAY", nil, subLevel + 2)
        fill:SetPoint("TOPLEFT", outline, "TOPLEFT", EXPAND_OUTLINE_WIDTH, -EXPAND_OUTLINE_WIDTH)
        fill:SetPoint("BOTTOMRIGHT", outline, "BOTTOMRIGHT", -EXPAND_OUTLINE_WIDTH, EXPAND_OUTLINE_WIDTH)
        fill:SetTexture(CLIP_MASK_TEXTURE)
        fill:SetGradient("VERTICAL", CreateColor(unpack(colors[2])), CreateColor(unpack(colors[1])))

        local highlight = expand:CreateTexture(nil, "OVERLAY", nil, subLevel + 3)
        highlight:SetHeight(1)
        highlight:SetPoint("TOPLEFT", fill, "TOPLEFT")
        highlight:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
        highlight:SetColorTexture(unpack(EXPAND_HIGHLIGHT))
        if i == 1 then
            -- N centered on the front frame.
            expand.Count = expand:CreateFontString(nil, "OVERLAY", nil)
            expand.Count:SetDrawLayer("OVERLAY", 7)
            expand.Count:SetFont(EXPAND_COUNT_FONT, EXPAND_COUNT_FONT_SIZE, "")
            expand.Count:SetTextColor(unpack(EXPAND_COUNT_COLOR))
            expand.Count:SetPoint("CENTER", fill, "CENTER", EXPAND_COUNT_X, 0)
        end
    end
    expand:Hide()
    wedge.ExpandBadge = expand
end

--- The visibility eye's atlas (crossed out with `hidden`), or nil when this client has no such art.
--- Also the settings preview's Hide Hidden Actions toggle.
function Ring_Layout.GetEyeAtlas(hidden)
    return FirstAtlas(hidden and CONDITION_HIDDEN_ATLASES or CONDITION_BADGE_ATLASES)
end

--- Eye badge on the icon's bottom-left corner: this slice hides when it has nothing to fire. The
--- hidden (crossed-out) eye means it's hidden right now.
function Private.CreateConditionBadge(wheel, wedge)
    local badge = CreateFrame("Frame", nil, wedge.Button)
    badge:SetFrameLevel(wheel:GetFrameLevel() + 9)
    badge:SetSize(CONDITION_BADGE_SIZE, CONDITION_BADGE_SIZE)
    badge:SetPoint("CENTER", wedge.Button, "BOTTOMLEFT", CONDITION_BADGE_X, CONDITION_BADGE_Y)
    badge.Texture = badge:CreateTexture(nil, "OVERLAY")
    badge.Texture:SetAllPoints()

    local visibleAtlas = Ring_Layout.GetEyeAtlas(false)
    local hiddenAtlas = Ring_Layout.GetEyeAtlas(true)

    -- Fallback when there's no hidden-eye art: a dark line under a light one across the eye.
    local function Slash(thickness, r, g, b, a, subLevel)
        local line = badge:CreateLine(nil, "OVERLAY", nil, subLevel)
        line:SetThickness(thickness)
        line:SetColorTexture(r, g, b, a)
        line:SetStartPoint("TOPRIGHT", badge, -CONDITION_SLASH_INSET, -CONDITION_SLASH_INSET)
        line:SetEndPoint("BOTTOMLEFT", badge, CONDITION_SLASH_INSET, CONDITION_SLASH_INSET)
        line:Hide()
        return line
    end
    if not hiddenAtlas then
        badge.SlashShadow = Slash(CONDITION_SLASH_SHADOW_THICKNESS, 0, 0, 0, 0.85, 2)
        badge.Slash = Slash(CONDITION_SLASH_THICKNESS, 1, 1, 1, 1, 3)
    end

    function badge:SetHidden(hidden)
        if hidden and hiddenAtlas then
            self.Texture:SetAtlas(hiddenAtlas)
        elseif visibleAtlas then
            self.Texture:SetAtlas(visibleAtlas)
        else
            self.Texture:SetTexture(CONDITION_BADGE_TEXTURE)
        end
        if self.Slash then
            self.Slash:SetShown(hidden)
            self.SlashShadow:SetShown(hidden)
        end
    end
    badge:SetHidden(false)

    badge:Hide()
    wedge.ConditionBadge = badge
end



-- Showing them (wheel methods)

local WheelMixin = Private.WheelMixin

--- Badges on nested ring slices: the mouse wheel when they scroll, stacked frames with the
--- number of slices they add when they expand.
--- @param slices table the ring's own slices (not display slices, which resolve nested rings)
--- @param hideSingleScroll boolean|nil no mouse wheel on a scroll submenu with at most one action
---     shown right now: nothing to scroll to (the in-game menu; the preview always shows it)
function WheelMixin:SetScrollBadges(slices, hideSingleScroll)
    for i = 1, #self.Wedges do
        local slice = i <= (self.sliceCount or 0) and slices[i] or nil
        local scrolls = Ring_Live.IsScroll(slice)
        if scrolls and hideSingleScroll then scrolls = #Ring_Live.GetScrollSlices(slice) > 1 end
        self.Wedges[i].ScrollBadge:SetShown(scrolls)
        local expand = self.Wedges[i].ExpandBadge
        local spread = Ring_Live.IsSpread(slice)
        expand:SetShown(spread)
        if spread then
            expand.Count:SetText(math.min(Ring_Live.CountSpread(slice), EXPAND_COUNT_MAX))
        end
    end
end

--- Shows the visibility badge on slices that hide when they have nothing to fire (preview only),
--- slashed on the ones hidden right now.
--- @param slices table|nil the ring's own slices; nil hides every badge
function WheelMixin:SetConditionBadges(slices)
    for i = 1, #self.Wedges do
        local slice = slices and i <= (self.sliceCount or 0) and slices[i]
        local badge = self.Wedges[i].ConditionBadge
        local hasCondition = slice and Ring_Actions.GetVisibilityCondition(slice) ~= nil or false
        badge:SetShown(hasCondition)
        if hasCondition then badge:SetHidden(not Ring_Actions.IsSliceAvailable(slice)) end
    end
end

--- Eye badge on the center when the quick action's slice can hide (slashed while hidden). nil
--- hides it. Preview only.
function WheelMixin:SetQuickBadges(slice)
    local badges = self.QuickBadges
    local hasCondition = slice and Ring_Actions.GetVisibilityCondition(slice) ~= nil or false
    badges.ConditionBadge:SetShown(hasCondition)
    if hasCondition then badges.ConditionBadge:SetHidden(not Ring_Actions.IsSliceAvailable(slice)) end
end
