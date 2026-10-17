local env = select(2, ...)
local Setting_Enum = env.AX_Modules:New("@\\Setting\\Enum")

Setting_Enum.WidgetType = {
    Tab           = 1,
    Title         = 2,
    Container     = 3,
    Text          = 4,
    Range         = 5,
    Button        = 6,
    CheckButton   = 7,
    SelectionMenu = 8,
    ColorInput    = 9,
    Input         = 10,
    Custom        = 11
}

Setting_Enum.ImageType = {
    Large = 1,
    Small = 2
}

-- CallbackRegistry events the settings fire. Comments show what each passes to its callbacks.
-- The README's Refreshing section has more.
Setting_Enum.Event = {
    Refresh     = "Setting.Refresh",     -- widgets re-read their values and showWhen / disableWhen, passes force
    HostChanged = "Setting.HostChanged", -- the settings moved or closed, passes a Host value or nil
}

-- Where the settings are shown (Setting.GetHost).
Setting_Enum.Host = {
    Options = "options", -- the game's Options panel, under AddOns
    Window  = "window",  -- the settings' own window
}
