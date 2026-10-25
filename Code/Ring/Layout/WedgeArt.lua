--[[
    Ring_Layout (see Geometry.lua): the art shown behind a highlighted wedge. It's Blizzard's art
    for the menu's count when there is some, our own for 2 and 3 actions, or copies of the 4-slice
    art clipped to the wedge's sector. Wheel.lua sets it up for each wedge (SetupWedgeArt) and
    shows it while the wedge is highlighted (SetWedgeArtShown).
]]

local env = select(2, ...)
local Path = env.AX_Modules:Import("ax_modules\\path")
local Private = env.AX_Modules:Import("@\\Ring\\Layout\\Private")

local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi

local ATLAS_WEDGE = "Radial_Wheel_Select_Wedge_Count_%d"
local CLIP_MASK_SIZE = 512 -- large enough to cover the whole wedge art along each edge

-- Our own highlight art for 2 and 3 actions (Blizzard has none, and copies of the 4-slice art show
-- seams). In Art/Ring/Wedge_Count_N.png, the wheel center is the image center, the wedge points
-- right, and its inner arc is at CUSTOM_WEDGE_INNER_FRAC of the half size. It's sized so that arc
-- sits on the center circle.
local CUSTOM_WEDGE_PATH = "%s\\Art\\Ring\\Wedge_Count_%d.png"
local CUSTOM_WEDGE_COUNTS = { [2] = true, [3] = true }
-- Baked into the images (made with a script kept outside the repo), so change both together.
local CUSTOM_WEDGE_INNER_FRAC = 0.11

-- The widest share of a wedge that one copy of the 4-slice art (90 degrees wide) may cover. It's
-- below 90 so each copy's own straight edges are always clipped away. A wider wedge (fewer than 4
-- actions) is drawn as several rotated copies side by side.
local MAX_PIECE_ARC = rad(80)

--- Piece `index` of a wedge's highlight art, made on first use. It's one copy of the art, plus two
--- half-plane masks whose edges run along its sector's boundary lines through the wheel center.
--- Together the masks cut the art down to exactly that sector, and leave Blizzard's inner arc
--- around the cancel button untouched.
---@param wedge RingWedge
---@param index integer
---@return table piece { texture, masks, clipped }
local function GetPiece(wedge, index)
    local piece = wedge.Pieces[index]
    if piece then return piece end

    piece = { texture = wedge:CreateTexture(nil, "ARTWORK"), masks = {} }
    for i = 1, 2 do
        local mask = wedge:CreateMaskTexture()
        mask:SetTexture(Private.WHITE_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(CLIP_MASK_SIZE, CLIP_MASK_SIZE)
        piece.masks[i] = mask
    end
    piece.texture:Hide()
    wedge.Pieces[index] = piece
    return piece
end

---@param piece table
---@param clipped boolean
local function SetPieceClipped(piece, clipped)
    if piece.clipped == clipped then return end
    for _, mask in ipairs(piece.masks) do
        if clipped then piece.texture:AddMaskTexture(mask) else piece.texture:RemoveMaskTexture(mask) end
    end
    piece.clipped = clipped
end

--- Clips `piece` to the sector between angles `low` and `high` (radians, around the wheel center).
---@param piece table
---@param wedge RingWedge
---@param wedgeAngle number the wedge's angle, which places the wedge frame the masks are anchored to
---@param low number
---@param high number
local function ClipPiece(piece, wedge, wedgeAngle, low, high)
    -- The wheel center, relative to the wedge frame's center.
    local centerX, centerY = -cos(wedgeAngle) * Private.WEDGE_SPACING, -sin(wedgeAngle) * Private.WEDGE_SPACING
    local edges = {
        { angle = high, inward = high - pi / 2 },
        { angle = low,  inward = low + pi / 2 },
    }
    local distance = CLIP_MASK_SIZE / 2
    for i, edge in ipairs(edges) do
        local mask = piece.masks[i]
        mask:ClearAllPoints()
        mask:SetPoint("CENTER", wedge, "CENTER", centerX + cos(edge.inward) * distance, centerY + sin(edge.inward) * distance)
        mask:SetRotation(edge.angle)
    end
    SetPieceClipped(piece, true)
end

--- Rotates `piece` to `angle`, and places it where Blizzard draws a wedge at that angle.
---@param piece table
---@param wedgeAngle number
---@param angle number
local function PlacePiece(piece, wedgeAngle, angle)
    local radius = Private.WEDGE_SPACING + Private.WEDGE_SELECTED_SPACING
    local texture = piece.texture
    texture:SetRotation(angle)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", cos(angle) * radius - cos(wedgeAngle) * Private.WEDGE_SPACING,
        sin(angle) * radius - sin(wedgeAngle) * Private.WEDGE_SPACING)
end

--- Sets up the art shown behind `wedge` while it's highlighted, for a menu of `count` actions.
---@param wedge RingWedge
---@param count integer
---@param angle number the wedge's angle
function Private.SetupWedgeArt(wedge, count, angle)
    local wedgeAtlas = ATLAS_WEDGE:format(count)
    local pieceCount

    if count < 2 then
        pieceCount = 0 -- a single action sits in the center and never shows wedge art
    elseif Private.HasAtlas(wedgeAtlas) then
        -- Blizzard's art made for this count, as one unclipped copy.
        local piece = GetPiece(wedge, 1)
        piece.texture:SetAtlas(wedgeAtlas, true)
        SetPieceClipped(piece, false)
        PlacePiece(piece, angle, angle)
        pieceCount = 1
    elseif CUSTOM_WEDGE_COUNTS[count] then
        local piece = GetPiece(wedge, 1)
        local size = 2 * Private.GetDividerStartRadius() / CUSTOM_WEDGE_INNER_FRAC
        piece.texture:SetTexture(CUSTOM_WEDGE_PATH:format(Path.Root, count))
        piece.texture:SetSize(size, size)
        SetPieceClipped(piece, false)
        -- Centered on the wheel center (given relative to the wedge frame), rotated to the wedge.
        piece.texture:SetRotation(angle)
        piece.texture:ClearAllPoints()
        piece.texture:SetPoint("CENTER", -cos(angle) * Private.WEDGE_SPACING, -sin(angle) * Private.WEDGE_SPACING)
        pieceCount = 1
    else
        -- The 4-slice art at its own size, clipped to this wedge's sector. That's one copy for a
        -- narrower wedge (more than 4), or several rotated copies side by side for a wider one.
        local arc = 2 * pi / count
        pieceCount = math.ceil(arc / MAX_PIECE_ARC)
        local pieceArc = arc / pieceCount
        local low = angle - arc / 2
        local fallbackAtlas = ATLAS_WEDGE:format(Private.FALLBACK_WEDGE_COUNT)
        for i = 1, pieceCount do
            local piece = GetPiece(wedge, i)
            local pieceLow = low + (i - 1) * pieceArc
            piece.texture:SetAtlas(fallbackAtlas, true)
            PlacePiece(piece, angle, pieceLow + pieceArc / 2)
            ClipPiece(piece, wedge, angle, pieceLow, pieceLow + pieceArc)
        end
    end

    wedge.pieceCount = pieceCount
    for i = pieceCount + 1, #wedge.Pieces do
        wedge.Pieces[i].texture:Hide()
    end
end

--- Shows or hides `wedge`'s highlight art.
---@param wedge RingWedge
---@param shown boolean
function Private.SetWedgeArtShown(wedge, shown)
    for i = 1, #wedge.Pieces do
        wedge.Pieces[i].texture:SetShown(shown and i <= (wedge.pieceCount or 0))
    end
end
