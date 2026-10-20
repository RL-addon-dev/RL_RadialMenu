local addonName, env = ...
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
local Utils_Standard = env.AX_Modules:Import("ax_modules\\utils\\standard")
local WoWClient_Events = env.AX_Modules:New("ax_modules\\wow-client\\events")

local CreateFrame = CreateFrame
local GetTime = GetTime

-- The CallbackRegistry events this module fires (WoWClient.Event). Listen with
-- CallbackRegistry.Add(WoWClient.Event.OnAddonLoaded, callback).
WoWClient_Events.Event = Utils_Standard.Strict({
    OnAddonLoaded    = "WoWClient.OnAddonLoaded",    -- this addon's ADDON_LOADED (saved variables are there)
    OnUIScaleChanged = "WoWClient.OnUIScaleChanged", -- the UI scale changed, once it settles
    OnKeyDown        = "WoWClient.OnKeyDown",        -- a key went down, passes the key
    OnKeyUp          = "WoWClient.OnKeyUp",          -- a key went up, passes the key
    OnEscapePressed  = "WoWClient.OnEscapePressed",  -- Escape went down
}, "WoWClient event")

do -- UI Scale Changed
    local lastChangedTime = 0
    local scaleChangeDebounceTime = 0.25

    local awaitScaleEnd = CreateFrame("Frame")
    awaitScaleEnd:SetScript("OnUpdate", function()
        if GetTime() < lastChangedTime + scaleChangeDebounceTime then return end
        awaitScaleEnd:Hide()
        CallbackRegistry.Trigger(WoWClient_Events.Event.OnUIScaleChanged)
    end)

    local f = CreateFrame("Frame")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:SetScript("OnEvent", function(self, event, ...)
        lastChangedTime = GetTime()
        awaitScaleEnd:Show()
    end)
end

do -- Addon Loaded
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_LOADED" then
            local name = ...
            if name == addonName then
                CallbackRegistry.Trigger(WoWClient_Events.Event.OnAddonLoaded)
            end
        end
    end)
end

do -- Mouse
    WoWClient_Events.IsPlayerTurning = false
    WoWClient_Events.IsPlayerLooking = false

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_STARTED_LOOKING")
    f:RegisterEvent("PLAYER_STOPPED_LOOKING")
    f:RegisterEvent("PLAYER_STARTED_TURNING")
    f:RegisterEvent("PLAYER_STOPPED_TURNING")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_STARTED_TURNING" or event == "PLAYER_STOPPED_TURNING" then
            WoWClient_Events.IsPlayerTurning = (event == "PLAYER_STARTED_TURNING")
        end
        if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
            WoWClient_Events.IsPlayerLooking = (event == "PLAYER_STARTED_MOVING")
        end
    end)
end
