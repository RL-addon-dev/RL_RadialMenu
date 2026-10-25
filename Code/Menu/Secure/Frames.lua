--[[
    Menu_Secure (see Snippets.lua): the secure frames, and the names the files share.
        - The controller, whose restricted environment the snippets share.
        - The screen and the center probe they measure with.
        - The helper, which the temporary bindings click while a menu is open.
        - Clear Markers.
        - The secure attribute and click names the insecure side uses (Menu_Secure.Attribute,
          Menu_Secure.Click). The snippets spell the same names out, because they can't see Lua
          constants, so a rename has to change both.
]]

local env = select(2, ...)
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local Menu_Secure = env.AX_Modules:Import("@\\Menu\\Secure")
local Private = env.AX_Modules:Import("@\\Menu\\Secure\\Private")

-- A menu button's own secure attributes, set out of combat (Setup.lua) and read by the snippets.
-- The ones ending in "-" take a wedge index after them ("menu-scroll-3").
Menu_Secure.Attribute = Utils_Standard.Strict({
    Id          = "menu-id",          -- the menu's id
    Count       = "menu-count",       -- how many wedges the live menu has
    Deadzone    = "menu-deadzone",    -- Distance to Select, in px
    ProbeSize   = "menu-probe",       -- the center probe's side, in px
    Origin      = "menu-origin",      -- "menu" with Select From = Menu Center (Menu_Secure.ORIGIN_MENU)
    CenterX     = "menu-centerx",     -- the fixed menu's center, for Select From = Menu Center
    CenterY     = "menu-centery",
    Quick       = "menu-quick",       -- what a tap fires: a wedge index, or the quick action's suffix
    Last        = "menu-last",        -- the wedge a Last Used action fires
    First       = "menu-first",       -- the wedge a First Action fires
    ScrollCount = "menu-scrollcount-", -- a scroll submenu's action count, by wedge index
    Scroll      = "menu-scroll-",     -- a scroll submenu's shown action, by wedge index
    HasScroll   = "menu-hasscroll",   -- the menu has a scroll submenu (the wheel and D-pad scroll)
    StealFocus  = "menu-stealfocus",  -- Cursor + Focus: the press may steal your focus
    Aimed       = "menu-aimed",       -- this open's target markers already point at a unit
    KeyMods     = "menu-keymods",     -- the keybind's modifier prefix ("CTRL-")
    KeyBase     = "menu-keybase",     -- the keybind without modifiers, left to the menu while open
    RightClick  = "menu-rightclick",  -- Right-Click to Cancel
    Relaxed     = "menu-relaxed",     -- Menu Style is Relaxed (always in the gamepad UI)
    Flick       = "menu-flick",       -- Flick to Select
    Sticky      = "menu-sticky",      -- the wedge a controller's right stick last aimed at
    -- A stick dispatcher's (Keys.lua), by side ("TOP", "LEFT", "RIGHT", "BOTH").
    Menu        = "side-",            -- the menu button that side opens
    Modifier    = "modifier-",        -- a crossbar modifier's button index ("LEFT", "RIGHT")
}, "secure attribute")

-- Menu_Secure.Attribute.Origin's value with Select From = Menu Center.
Menu_Secure.ORIGIN_MENU = "menu"

-- The clicks the insecure side sends or binds. The snippets also use "RelaxedSelect", "PadUse",
-- "Aim", "Dismiss", "PadUp", "PadDown", "WheelUp" and "WheelDown" among themselves.
Menu_Secure.Click = Utils_Standard.Strict({
    Gamepad    = "Gamepad",    -- a controller's open (a controller button, a crossbar macro, a stick)
    LeftButton = "LeftButton", -- any other keybind's open
    FocusSteal = "FocusSteal", -- Cursor + Focus: steals your focus on the press
    FocusClear = "FocusClear", -- Cursor + Focus: clears it on the way out
}, "secure click")

local Controller = CreateFrame("Frame", "RLRM_Controller", UIParent, "SecureHandlerBaseTemplate") --[[@as Frame]]
Controller:SetAttribute("BindPad", Private.BIND_PAD)
Controller:SetAttribute("UnbindPad", Private.UNBIND_PAD)

local Screen = CreateFrame("Frame", "RLRM_Screen", UIParent, "SecureFrameTemplate") --[[@as Frame]]
Screen:SetAllPoints(UIParent)

local Probe = CreateFrame("Frame", "RLRM_CenterProbe", UIParent, "SecureFrameTemplate") --[[@as Frame]]
Probe:SetSize(4, 4)
Probe:Hide()

-- Cursor + Focus: the macro the focus clear click runs (on menu buttons, and on the helper too).
-- The steal click is a focus action instead (Setup.lua).
Private.FOCUS_CLEAR_TEXT = "/clearfocus"

local Helper = CreateFrame("Button", "RLRM_MenuHelper", UIParent, "SecureActionButtonTemplate") --[[@as Button]]
Helper:SetSize(1, 1)
Helper:EnableMouse(false)
Helper:RegisterForClicks("AnyDown")
-- Its bindings click on key down, and fire then (a dismiss clearing a stolen focus).
Helper:SetAttribute("useOnKeyDown", true)
Helper:SetAttribute("*type-" .. Menu_Secure.Click.FocusClear, "macro")
Helper:SetAttribute("*macrotext-" .. Menu_Secure.Click.FocusClear, Private.FOCUS_CLEAR_TEXT)
SecureHandlerWrapScript(Helper, "OnClick", Controller, Private.HELPER_CLICK)

-- Clears every target marker, for a Clear target marker that also clears a stolen focus. A macro
-- can't clear them all, so its copy clicks this, then clears the focus.
local ClearMarkers = CreateFrame("Button", "RLRM_ClearMarkers", UIParent, "SecureActionButtonTemplate") --[[@as Button]]
ClearMarkers:SetSize(1, 1)
ClearMarkers:EnableMouse(false)
ClearMarkers:RegisterForClicks("AnyUp") -- /click sends a release
ClearMarkers:SetAttribute("useOnKeyDown", false)
ClearMarkers:SetAttribute("type", "raidtarget")
ClearMarkers:SetAttribute("action", "clear-all")

Private.Controller, Private.Screen, Private.Probe = Controller, Screen, Probe
Private.Helper, Private.ClearMarkers = Helper, ClearMarkers

-- Live menus by id (Setup.lua), and their secure buttons. Buttons are created once, then reused,
-- because frames can't be destroyed.
Private.menusById = {}
Private.buttonsById = {}

-- The button suffix of the tap-only quick action ("*type-sQ"...), and its "menu-quick" value.
Private.QUICK_SUFFIX = "Q"
