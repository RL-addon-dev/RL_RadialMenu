--[[
    Menu_Layout: the badges on an action icon's corners.
        scroll      a mouse wheel, on a submenu that scrolls (in game and in the preview)
        spread      stacked frames with a count, on a submenu spread into this menu (preview)
        visibility  an eye, on an action that hides when it has nothing to fire, crossed out while
                    hidden (preview, also on the center for the quick action)
    Wheel.lua creates them for each wedge, and the WheelMixin methods at the end of this file show
    them.
]]

local env = select(2, ...)
local Menu_Actions = env.AX_Modules:Import("@\\Menu\\Actions")
local Menu_Live = env.AX_Modules:Import("@\\Menu\\Live")
local Menu_Layout = env.AX_Modules:Import("@\\Menu\\Layout")
local Private = env.AX_Modules:Import("@\\Menu\\Layout\\Private")

-- Badges sit this many levels above the wheel, over its art and icons.
local BADGE_FRAME_LEVEL = 9

-- The scroll badge: Blizzard's mouse art, the first one this client has. That's the new player
-- tutorial's middle button (wheel) icon, else the click-casting window's mouse icon, else a small
-- "Scroll" text pill.
local SCROLL_BADGE_ATLASES = { "newplayertutorial-icon-mouse-middlebutton", "clickcast-icon-mouse" }
-- A menu opened by a controller scrolls with the D-pad, so it shows the D-pad (up and down) art
-- instead, when the client has it (WoW Forever's gamepad UI, whose D-pad shapes are shared by
-- every controller family), else the game's D-pad up icon for the current controller
-- (ConsolePort in retail).
local SCROLL_BADGE_PAD_ATLASES = { "gamepad-ps-dpadupdown-normal" }
local SCROLL_BADGE_SIZE = 30
-- Its center's offset from the icon's bottom-left corner (the item count is bottom-right).
local SCROLL_BADGE_X, SCROLL_BADGE_Y = 1, 1
local SCROLL_PILL_WIDTH  = 44
local SCROLL_PILL_HEIGHT = 14
local SCROLL_PILL_OFFSET = 4 -- how far the pill tucks under the icon
local SCROLL_PILL_COLOR  = { 0, 0, 0, 0.8 }

-- The visibility badge (settings preview): an eye, or Blizzard's hidden (crossed-out) eye while
-- the action is hidden. The first art this client has wins. Without a hidden eye, a slash is
-- drawn over the eye instead.
local CONDITION_BADGE_ATLASES = { "GM-icon-visible", "transmog-icon-visible", "socialqueuing-icon-eye" }
local CONDITION_HIDDEN_ATLASES = { "GM-icon-visibleDis", "GM-icon-hidden", "transmog-icon-hidden", "socialqueuing-icon-eye-hidden" }
local CONDITION_BADGE_TEXTURE = "Interface\\Common\\help-i"
local CONDITION_BADGE_SIZE = 56
local CONDITION_BADGE_X, CONDITION_BADGE_Y = -1, 1 -- center offset from the icon's bottom-right corner
local CONDITION_SLASH_INSET = 4 -- the slash runs corner to corner, this far in
local CONDITION_SLASH_THICKNESS = 2.5
local CONDITION_SLASH_SHADOW_THICKNESS = 5
local CONDITION_SLASH_COLOR = { 1, 1, 1, 1 }
local CONDITION_SLASH_SHADOW_COLOR = { 0, 0, 0, 0.85 }

-- The spread submenu badge (settings preview): a small stack of square frames, like a fanned hand
-- of cards ("this is several actions"), with how many actions it adds right now on the front one.
-- Counts above SPREAD_COUNT_MAX show as that.
local SPREAD_STACK_FRAMES = 3
local SPREAD_STACK_SIZE = 18 -- each frame
local SPREAD_STACK_STEP = 2  -- offset between frames, up and to the right
-- Grey, like the visibility eye, with the back frames darker so the stack reads as layers. Each
-- fill is a top-to-bottom gradient (top, bottom) with a faint highlight line along its top edge
-- and a soft drop shadow, for the same shaded look as the mouse and eye art.
local SPREAD_FILL_BACK  = { { 0.72, 0.72, 0.72 }, { 0.48, 0.48, 0.48 } }
local SPREAD_FILL_FRONT = { { 0.92, 0.92, 0.92 }, { 0.64, 0.64, 0.64 } }
local SPREAD_HIGHLIGHT  = { 1, 1, 1, 0.55 }
local SPREAD_SHADOW     = { 0, 0, 0, 0.45 }
local SPREAD_SHADOW_OFFSET = 1
local SPREAD_OFFSET_X, SPREAD_OFFSET_Y = 3, 1 -- the badge's center from the icon's bottom-left corner
local SPREAD_OUTLINE = { 0, 0, 0, 0.9 }
local SPREAD_OUTLINE_WIDTH = 1
-- Each frame uses 4 sublevels (shadow, outline, fill, highlight), the back frame lowest.
local SPREAD_FIRST_SUBLEVEL = -8
local SPREAD_SUBLEVELS_PER_FRAME = 4
local SPREAD_COUNT_COLOR = { 0.08, 0.08, 0.08 }
local SPREAD_COUNT_FONT = "Fonts\\FRIZQT__.TTF"
local SPREAD_COUNT_FONT_SIZE = 8
local SPREAD_COUNT_SUBLEVEL = 7
local SPREAD_COUNT_X = 0
local SPREAD_COUNT_MAX = 99


---@class ScrollBadge : Frame
---@field Texture Texture? the mouse or D-pad art (none on the text pill)
---@field mouseAtlas string?
---@field padAtlas string?
---@field Background Texture? the text pill's
---@field Text FontString? the text pill's

---@class SpreadBadge : Frame
---@field Count FontString

---@class ConditionBadge : Frame
---@field Texture Texture
---@field Slash Line? drawn over the eye when there's no hidden eye art
---@field SlashShadow Line?
---@field SetHidden fun(self: ConditionBadge, hidden: boolean)


--- The first of `names` this client has, or nil.
---@param names string[]
---@return string?
local function FirstAtlas(names)
    for _, name in ipairs(names) do
        if Private.HasAtlas(name) then return name end
    end
end

--- A frame for a badge on `wedge`'s icon, above the wheel. It's a child of the icon, so it follows
--- the open and close slide and the selected scale.
---@param wheel MenuWheel
---@param wedge MenuWedge|table
---@return Frame
local function CreateBadgeFrame(wheel, wedge)
    local badge = CreateFrame("Frame", nil, wedge.Button)
    badge:SetFrameLevel(wheel:GetFrameLevel() + BADGE_FRAME_LEVEL)
    return badge
end



-- Scroll and spread submenu badges

--- The mouse wheel art on the icon's bottom-left corner, clear of the item count, or a "Scroll"
--- pill below the icon on clients without it.
---@param wheel MenuWheel
---@param wedge MenuWedge
local function CreateScrollBadgeArt(wheel, wedge)
    local badge = CreateBadgeFrame(wheel, wedge) --[[@as ScrollBadge]]

    local atlas = FirstAtlas(SCROLL_BADGE_ATLASES)
    if atlas then
        badge:SetSize(SCROLL_BADGE_SIZE, SCROLL_BADGE_SIZE)
        badge:SetPoint("CENTER", wedge.Button, "BOTTOMLEFT", SCROLL_BADGE_X, SCROLL_BADGE_Y)
        badge.Texture = badge:CreateTexture(nil, "OVERLAY")
        badge.Texture:SetAllPoints()
        badge.Texture:SetAtlas(atlas)
        badge.mouseAtlas = atlas
        badge.padAtlas = FirstAtlas(SCROLL_BADGE_PAD_ATLASES)
    else
        badge:SetSize(SCROLL_PILL_WIDTH, SCROLL_PILL_HEIGHT)
        badge:SetPoint("TOP", wedge.Button, "BOTTOM", 0, SCROLL_PILL_OFFSET)
        badge.Background = badge:CreateTexture(nil, "BACKGROUND")
        badge.Background:SetAllPoints()
        badge.Background:SetColorTexture(unpack(SCROLL_PILL_COLOR))
        badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge.Text:SetPoint("CENTER")
        badge.Text:SetText(env.L["Config - Menus - Submenu - Badge"])
    end

    badge:Hide()
    wedge.ScrollBadge = badge
end

--- One frame of the spread badge's stack, `offset` px up and to the right. Each frame covers the
--- frames behind it, in one draw layer. It's a shadow, a dark outline, a fill inset by the outline
--- and a highlight line. These are plain squares, because rounded frame art left edge artifacts at
--- this size.
---@param badge Frame
---@param offset number
---@param subLevel integer its first sublevel
---@param colors table the fill's top and bottom colors
---@return Texture fill
local function CreateStackFrame(badge, offset, subLevel, colors)
    local shadow = badge:CreateTexture(nil, "OVERLAY", nil, subLevel)
    shadow:SetSize(SPREAD_STACK_SIZE, SPREAD_STACK_SIZE)
    shadow:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", offset + SPREAD_SHADOW_OFFSET, offset - SPREAD_SHADOW_OFFSET)
    shadow:SetColorTexture(unpack(SPREAD_SHADOW))

    local outline = badge:CreateTexture(nil, "OVERLAY", nil, subLevel + 1)
    outline:SetSize(SPREAD_STACK_SIZE, SPREAD_STACK_SIZE)
    outline:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", offset, offset)
    outline:SetColorTexture(unpack(SPREAD_OUTLINE))

    local fill = badge:CreateTexture(nil, "OVERLAY", nil, subLevel + 2)
    fill:SetPoint("TOPLEFT", outline, "TOPLEFT", SPREAD_OUTLINE_WIDTH, -SPREAD_OUTLINE_WIDTH)
    fill:SetPoint("BOTTOMRIGHT", outline, "BOTTOMRIGHT", -SPREAD_OUTLINE_WIDTH, SPREAD_OUTLINE_WIDTH)
    fill:SetTexture(Private.WHITE_TEXTURE)
    fill:SetGradient("VERTICAL", CreateColor(unpack(colors[2])), CreateColor(unpack(colors[1])))

    local highlight = badge:CreateTexture(nil, "OVERLAY", nil, subLevel + 3)
    highlight:SetHeight(1)
    highlight:SetPoint("TOPLEFT", fill, "TOPLEFT")
    highlight:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    highlight:SetColorTexture(unpack(SPREAD_HIGHLIGHT))
    return fill
end

--- The spread badge, in the scroll badge's spot: stacked frames, the back one first so the front
--- one draws on top, with the count on the front one.
---@param wheel MenuWheel
---@param wedge MenuWedge
local function CreateSpreadBadge(wheel, wedge)
    local span = SPREAD_STACK_SIZE + (SPREAD_STACK_FRAMES - 1) * SPREAD_STACK_STEP
    local badge = CreateBadgeFrame(wheel, wedge) --[[@as SpreadBadge]]
    badge:SetSize(span, span)
    badge:SetPoint("CENTER", wedge.Button, "BOTTOMLEFT", SPREAD_OFFSET_X, SPREAD_OFFSET_Y)
    for i = SPREAD_STACK_FRAMES, 1, -1 do
        local subLevel = SPREAD_FIRST_SUBLEVEL + (SPREAD_STACK_FRAMES - i) * SPREAD_SUBLEVELS_PER_FRAME
        local fill = CreateStackFrame(badge, (i - 1) * SPREAD_STACK_STEP, subLevel,
            (i == 1 and SPREAD_FILL_FRONT) or SPREAD_FILL_BACK)
        if i == 1 then
            badge.Count = badge:CreateFontString(nil, "OVERLAY", nil)
            badge.Count:SetDrawLayer("OVERLAY", SPREAD_COUNT_SUBLEVEL)
            badge.Count:SetFont(SPREAD_COUNT_FONT, SPREAD_COUNT_FONT_SIZE, "")
            badge.Count:SetTextColor(unpack(SPREAD_COUNT_COLOR))
            badge.Count:SetPoint("CENTER", fill, "CENTER", SPREAD_COUNT_X, 0)
        end
    end
    badge:Hide()
    wedge.SpreadBadge = badge
end

--- The scroll and spread submenu badges for `wedge`.
---@param wheel MenuWheel
---@param wedge MenuWedge
function Private.CreateScrollBadge(wheel, wedge)
    CreateScrollBadgeArt(wheel, wedge)
    CreateSpreadBadge(wheel, wedge)
end



-- Visibility badge

--- The visibility eye's atlas (crossed out with `hidden`), or nil when this client has no such
--- art. The settings preview's Hide Hidden Actions toggle uses it too.
---@param hidden boolean
---@return string?
function Menu_Layout.GetEyeAtlas(hidden)
    return FirstAtlas(hidden and CONDITION_HIDDEN_ATLASES or CONDITION_BADGE_ATLASES)
end

--- The eye badge on the icon's bottom-right corner, meaning the action hides when it has nothing
--- to fire. The hidden (crossed-out) eye means it's hidden right now.
---@param wheel MenuWheel
---@param wedge MenuWedge|table a wedge, or the wheel's QuickBadges
function Private.CreateConditionBadge(wheel, wedge)
    local badge = CreateBadgeFrame(wheel, wedge) --[[@as ConditionBadge]]
    badge:SetSize(CONDITION_BADGE_SIZE, CONDITION_BADGE_SIZE)
    badge:SetPoint("CENTER", wedge.Button, "BOTTOMRIGHT", CONDITION_BADGE_X, CONDITION_BADGE_Y)
    badge.Texture = badge:CreateTexture(nil, "OVERLAY")
    badge.Texture:SetAllPoints()

    local visibleAtlas = Menu_Layout.GetEyeAtlas(false)
    local hiddenAtlas = Menu_Layout.GetEyeAtlas(true)

    -- Without hidden eye art, a dark line under a light one across the eye.
    local function Slash(thickness, color, subLevel)
        local line = badge:CreateLine(nil, "OVERLAY", nil, subLevel)
        line:SetThickness(thickness)
        line:SetColorTexture(unpack(color))
        line:SetStartPoint("TOPRIGHT", badge, -CONDITION_SLASH_INSET, -CONDITION_SLASH_INSET)
        line:SetEndPoint("BOTTOMLEFT", badge, CONDITION_SLASH_INSET, CONDITION_SLASH_INSET)
        line:Hide()
        return line
    end
    if not hiddenAtlas then
        badge.SlashShadow = Slash(CONDITION_SLASH_SHADOW_THICKNESS, CONDITION_SLASH_SHADOW_COLOR, 2)
        badge.Slash = Slash(CONDITION_SLASH_THICKNESS, CONDITION_SLASH_COLOR, 3)
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

--- Shows the eye on `badge` when `action` can hide, crossed out while it's hidden.
---@param badge ConditionBadge
---@param action Action?
local function ShowConditionBadge(badge, action)
    local hasCondition = action and Menu_Actions.GetVisibilityCondition(action) ~= nil or false
    badge:SetShown(hasCondition)
    if hasCondition then badge:SetHidden(not Menu_Actions.IsActionAvailable(action)) end
end



-- Showing them (wheel methods)

---@class MenuWheel
local WheelMixin = Private.WheelMixin

--- The game's D-pad up icon for the current controller, from its binding text, or nil.
---@return string?
local function GetPadUpAtlas()
    local name = GetBindingText("PADDUP"):match("|A:([^:|]+)")
    return name and Private.HasAtlas(name) and name or nil
end

--- Badges on submenus: the mouse wheel when they scroll, and stacked frames with the number of
--- actions they add when they're spread.
---@param actions Action[] the menu's own actions (not what the wedges show, which resolves submenus)
---@param hideSingleScroll boolean? no mouse wheel on a scroll submenu with at most one action shown
---     right now, since there's nothing to scroll to (the in-game menu, the preview always shows it)
---@param pad boolean? opened by a controller, so it shows the D-pad, which scrolls it
function WheelMixin:SetScrollBadges(actions, hideSingleScroll, pad)
    local padUpAtlas = pad and GetPadUpAtlas()
    for i = 1, #self.Wedges do
        local action = i <= (self.actionCount or 0) and actions[i] or nil
        local scrolls = Menu_Live.IsScroll(action)
        if scrolls and hideSingleScroll then scrolls = #Menu_Live.GetScrollActions(action) > 1 end
        local badge = self.Wedges[i].ScrollBadge
        badge:SetShown(scrolls)
        if scrolls and badge.Texture then
            local padAtlas = pad and (badge.padAtlas or padUpAtlas)
            badge.Texture:SetAtlas((padAtlas or badge.mouseAtlas) --[[@as string]])
        end
        local spreadBadge = self.Wedges[i].SpreadBadge
        local spread = Menu_Live.IsSpread(action)
        spreadBadge:SetShown(spread)
        if spread then
            spreadBadge.Count:SetText(math.min(Menu_Live.CountSpread(action), SPREAD_COUNT_MAX) --[[@as string]]) -- takes numbers too
        end
    end
end

--- Shows the visibility badge on actions that hide when they have nothing to fire (preview only),
--- crossed out on the ones hidden right now.
---@param actions Action[]? the menu's own actions, or nil to hide every badge
function WheelMixin:SetConditionBadges(actions)
    for i = 1, #self.Wedges do
        ShowConditionBadge(self.Wedges[i].ConditionBadge, actions and i <= (self.actionCount or 0) and actions[i] or nil)
    end
end

--- The eye badge on the center when the quick action can hide (crossed out while hidden), or none
--- with nil. Preview only.
---@param action Action?
function WheelMixin:SetQuickBadges(action)
    ShowConditionBadge(self.QuickBadges.ConditionBadge, action)
end
