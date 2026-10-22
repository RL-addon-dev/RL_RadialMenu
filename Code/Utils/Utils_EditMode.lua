--[[
    Edit Mode for addon frames: while Blizzard's Edit Mode is open, an added frame shows Edit
    Mode's highlight and can be dragged. Clicking it selects it and opens a small dialog with an
    optional slider and Reset Position.

        Utils_EditMode.AddFrame(frame, {
            name    = "Radial Menu",                     -- shown on the frame and the dialog
            onMoved = function(point, x, y) end,         -- dropped, as an offset from UIParent
            onReset = function() end,                    -- Reset Position
            onEnter = function() end,                    -- Edit Mode opened (optional)
            onExit  = function() end,                    -- Edit Mode closed (optional)
            onLayout = function() end,                   -- the active layout changed (optional)
            slider  = { label, min, max, step, get, set }, -- one setting in the dialog (optional)
        })

    It uses Blizzard's templates for the look, but never registers the frame as an Edit Mode
    system, so Edit Mode itself is never tainted.
]]

local env = select(2, ...)
local Utils_EditMode = env.AX_Modules:New("@\\Utils\\EditMode")

-- The names saved positions use for Blizzard's two first preset layouts. They're saved data, so
-- they never change.
local LAYOUT_MODERN, LAYOUT_CLASSIC = "Modern", "Classic"
local DIALOG_WIDTH, DIALOG_PADDING = 320, 16

local entries = {} -- [frame] = { info, selection }
local selected -- the entry whose dialog is open

--- Whether Edit Mode is open.
---@return boolean
function Utils_EditMode.IsActive()
    return EditModeManagerFrame ~= nil and EditModeManagerFrame:IsShown()
end

--- The active Edit Mode layout's name. Blizzard numbers its presets first, then the custom layouts.
---@return string?
function Utils_EditMode.GetActiveLayoutName()
    local info = C_EditMode.GetLayouts()
    if info.activeLayout <= 2 then return info.activeLayout == 1 and LAYOUT_MODERN or LAYOUT_CLASSIC end
    local presets = EditModePresetLayoutManager.presetLayoutInfo
    local layout = presets[info.activeLayout] or info.layouts[info.activeLayout - #presets]
    return layout and layout.layoutName
end



-- The dialog

---@class EditModeDialog : Frame
---@field Title FontString
---@field CloseButton Button
---@field SliderLabel FontString
---@field Slider EditModeSlider
---@field ResetButton Button

---@class EditModeSlider : Frame
---@field Init fun(self, value: number, minValue: number, maxValue: number, steps: number, formatters: table)
---@field RegisterCallback fun(self, event: string, callback: function, owner: any)

---@class EditModeSelection : Frame
---@field ShowHighlighted fun(self)
---@field ShowSelected fun(self)
---@field ShowEditInstructions fun(self, shown: boolean)
---@field GetLabelText fun(self): string

local Dialog = CreateFrame("Frame", nil, UIParent, "DialogBorderTranslucentTemplate") --[[@as EditModeDialog]]
Dialog:SetSize(DIALOG_WIDTH, 120)
Dialog:SetFrameStrata("DIALOG")
Dialog:SetClampedToScreen(true)
Dialog:EnableMouse(true)
Dialog:SetMovable(true)
Dialog:RegisterForDrag("LeftButton")
Dialog:SetScript("OnDragStart", Dialog.StartMoving)
Dialog:SetScript("OnDragStop", Dialog.StopMovingOrSizing)
Dialog:Hide()

Dialog.Title = Dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
Dialog.Title:SetPoint("TOP", 0, -DIALOG_PADDING)

Dialog.CloseButton = CreateFrame("Button", nil, Dialog, "UIPanelCloseButton") --[[@as Button]]
Dialog.CloseButton:SetPoint("TOPRIGHT", -2, -2)

Dialog.SliderLabel = Dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
Dialog.SliderLabel:SetPoint("TOPLEFT", DIALOG_PADDING, -52)

Dialog.Slider = CreateFrame("Frame", nil, Dialog, "MinimalSliderWithSteppersTemplate") --[[@as EditModeSlider]]
Dialog.Slider:SetPoint("LEFT", Dialog.SliderLabel, "RIGHT", 8, 0)
Dialog.Slider:SetPoint("RIGHT", -DIALOG_PADDING, 0)
Dialog.Slider:SetHeight(32)

Dialog.ResetButton = CreateFrame("Button", nil, Dialog, "UIPanelButtonTemplate") --[[@as Button]]
Dialog.ResetButton:SetSize(DIALOG_WIDTH - 2 * DIALOG_PADDING, 24)
Dialog.ResetButton:SetPoint("BOTTOM", 0, DIALOG_PADDING)
Dialog.ResetButton:SetText(HUD_EDIT_MODE_RESET_POSITION)

Dialog.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    local slider = selected and selected.info.slider
    if slider and value ~= slider.get() then slider.set(value) end
end, Dialog)
Dialog.ResetButton:SetScript("OnClick", function()
    if selected then selected.info.onReset() end
end)

--- Fills the dialog for `entry` and shows it beside its frame.
---@param entry table
local function OpenDialog(entry)
    local info = entry.info
    Dialog.Title:SetText(info.name)
    local slider = info.slider
    Dialog.SliderLabel:SetShown(slider ~= nil)
    Dialog.Slider:SetShown(slider ~= nil)
    if slider then
        Dialog.SliderLabel:SetText(slider.label)
        Dialog.Slider:Init(slider.get(), slider.min, slider.max, (slider.max - slider.min) / slider.step, {
            [MinimalSliderWithSteppersMixin.Label.Right] = function(value) return tostring(value) end,
        })
    end
    Dialog:ClearAllPoints()
    Dialog:SetPoint("LEFT", entry.selection, "RIGHT", 16, 0)
    Dialog:Show()
end

--- Shows the current values again, after a setting changed elsewhere.
function Utils_EditMode.RefreshDialog()
    if selected and Dialog:IsShown() then OpenDialog(selected) end
end



-- Selection

--- Unselects the selected frame (its highlight stays while Edit Mode is open).
local function Deselect()
    if not selected then return end
    selected.selection:ShowHighlighted()
    selected = nil
    Dialog:Hide()
end

--- Selects `entry`, after Blizzard's own selected system (only one is ever selected).
---@param entry table
local function Select(entry)
    EditModeManagerFrame:ClearSelectedSystem()
    Deselect()
    selected = entry
    entry.selection:ShowSelected()
    OpenDialog(entry)
end

--- Reports where `frame` was dropped, as its center's offset from UIParent's center.
---@param frame Frame
---@param info table
local function OnDropped(frame, info)
    frame:StopMovingOrSizing()
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    info.onMoved("CENTER", x - parentX, y - parentY)
end

--- Adds `frame` to Edit Mode (see the header).
---@param frame Frame
---@param info table
function Utils_EditMode.AddFrame(frame, info)
    frame:SetMovable(true)
    frame:SetDontSavePosition(true) -- its position is the addon's, per layout

    local selection = CreateFrame("Frame", nil, frame, "EditModeSystemSelectionTemplate") --[[@as EditModeSelection]]
    selection:SetAllPoints()
    -- Over the frame's own textures. A shown frame's strata is never "PARENT", which the type allows.
    ---@diagnostic disable-next-line: param-type-mismatch
    selection:SetFrameStrata(frame:GetFrameStrata())
    selection:SetFrameLevel(frame:GetFrameLevel() + 10)
    selection:Hide()
    -- Blizzard's label asks its system for a name, and this frame isn't one.
    selection.GetLabelText = function(_) return info.name end
    selection:SetScript("OnMouseDown", function() Select(entries[frame]) end)
    selection:SetScript("OnDragStart", function() frame:StartMoving() end)
    selection:SetScript("OnDragStop", function() OnDropped(frame, info) end)
    selection:SetScript("OnEnter", function(self) self:ShowEditInstructions(true) end)
    selection:SetScript("OnLeave", function(self) self:ShowEditInstructions(false) end)

    entries[frame] = { info = info, selection = selection }
    if Utils_EditMode.IsActive() then selection:ShowHighlighted() end
end



-- Edit Mode's events

local function OnEnter()
    for _, entry in pairs(entries) do
        entry.selection:ShowHighlighted()
        if entry.info.onEnter then entry.info.onEnter() end
    end
end

local function OnExit()
    Deselect()
    for _, entry in pairs(entries) do
        entry.selection:Hide()
        if entry.info.onExit then entry.info.onExit() end
    end
end

local function OnLayout()
    for _, entry in pairs(entries) do
        if entry.info.onLayout then entry.info.onLayout() end
    end
end

if EditModeManagerFrame then
    EventRegistry:RegisterCallback("EditMode.Enter", OnEnter, Utils_EditMode)
    EventRegistry:RegisterCallback("EditMode.Exit", OnExit, Utils_EditMode)
    EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", OnLayout, Utils_EditMode)
    -- Selecting one of Blizzard's systems unselects ours.
    hooksecurefunc(EditModeManagerFrame, "SelectSystem", Deselect)
end
