--[[
    Ring_Secure (see Snippets.lua): the secure frames. The controller, whose restricted environment
    the snippets share; the screen and center probe they measure with; the helper the temporary
    bindings click while a menu is open; Clear Markers. Also the names and tables the files share.
]]

local env = select(2, ...)
local Private = env.AX_Modules:Import("@\\Ring\\Secure\\Private")

local Controller = CreateFrame("Frame", "RLRM_Controller", UIParent, "SecureHandlerBaseTemplate")

local Screen = CreateFrame("Frame", "RLRM_Screen", UIParent, "SecureFrameTemplate")
Screen:SetAllPoints(UIParent)

local Probe = CreateFrame("Frame", "RLRM_CenterProbe", UIParent, "SecureFrameTemplate")
Probe:SetSize(4, 4)
Probe:Hide()

-- Cursor + Focus: the clicks that steal and clear your focus (on ring buttons, the helper
-- too for FocusClear; the snippets spell the names out), and their macros.
local FOCUS_STEAL, FOCUS_STEAL_TEXT = "FocusSteal", "/focus [@mouseover]"
local FOCUS_CLEAR, FOCUS_CLEAR_TEXT = "FocusClear", "/clearfocus"

local Helper = CreateFrame("Button", "RLRM_RingHelper", UIParent, "SecureActionButtonTemplate")
Helper:SetSize(1, 1)
Helper:EnableMouse(false)
Helper:RegisterForClicks("AnyDown")
-- Its bindings click on key down: fire then (a dismiss clearing a stolen focus).
Helper:SetAttribute("useOnKeyDown", true)
Helper:SetAttribute("*type-" .. FOCUS_CLEAR, "macro")
Helper:SetAttribute("*macrotext-" .. FOCUS_CLEAR, FOCUS_CLEAR_TEXT)
SecureHandlerWrapScript(Helper, "OnClick", Controller, Private.HELPER_CLICK)

-- Clears every target marker, for a Clear target marker that also clears a stolen focus: a
-- macro can't clear them all, so its copy clicks this, then clears the focus.
local ClearMarkers = CreateFrame("Button", "RLRM_ClearMarkers", UIParent, "SecureActionButtonTemplate")
ClearMarkers:SetSize(1, 1)
ClearMarkers:EnableMouse(false)
ClearMarkers:RegisterForClicks("AnyUp") -- /click sends a release
ClearMarkers:SetAttribute("useOnKeyDown", false)
ClearMarkers:SetAttribute("type", "raidtarget")
ClearMarkers:SetAttribute("action", "clear-all")

-- Live rings by id (Setup.lua), and their secure buttons (created once, then reused: frames
-- can't be destroyed).
local ringsById = {}
local buttonsById = {}

-- Button suffix of the tap-only quick action ("*type-sQ" ...), and its "ring-quick" value.
local QUICK_SUFFIX = "Q"

Private.Controller, Private.Screen, Private.Probe = Controller, Screen, Probe
Private.Helper, Private.ClearMarkers = Helper, ClearMarkers
Private.FOCUS_STEAL, Private.FOCUS_STEAL_TEXT = FOCUS_STEAL, FOCUS_STEAL_TEXT
Private.FOCUS_CLEAR, Private.FOCUS_CLEAR_TEXT = FOCUS_CLEAR, FOCUS_CLEAR_TEXT
Private.QUICK_SUFFIX = QUICK_SUFFIX
Private.ringsById, Private.buttonsById = ringsById, buttonsById
