local env = select(2, ...)
local LazyTimer = env.AX_Modules:Import("ax_modules\\lazy-timer")
local UIKit_Renderer_Processor = env.AX_Modules:Import("ax_modules\\ui-kit\\renderer\\processor")
local UIKit_Renderer_Cleaner = env.AX_Modules:New("ax_modules\\ui-kit\\renderer\\cleaner")

local band = bit.band
local bor = bit.bor
local Processor_SizeStatic = UIKit_Renderer_Processor.SizeStatic
local Processor_SizeFit = UIKit_Renderer_Processor.SizeFit
local Processor_SizeFill = UIKit_Renderer_Processor.SizeFill
local Processor_PositionOffset = UIKit_Renderer_Processor.PositionOffset
local Processor_Anchor = UIKit_Renderer_Processor.Anchor
local Processor_Point = UIKit_Renderer_Processor.Point
local Processor_Layout = UIKit_Renderer_Processor.Layout
local Processor_ScrollBar = UIKit_Renderer_Processor.ScrollBar

UIKit_Renderer_Cleaner.onCooldown = false
UIKit_Renderer_Cleaner.requiresDependencyPass = false

local dirty = {}
local dirtyCount = 0
local waitingForWash = false
local hasBackwardActions = false
local batchDepth = 0

local FIELD_ACTIONS = "__cleaner_actions"
local ACTION_SIZE_STATIC = 1
local ACTION_SIZE_FIT = 2
local ACTION_SIZE_FILL = 4
local ACTION_POSITION_OFFSET = 8
local ACTION_ANCHOR = 16
local ACTION_POINT = 32
local ACTION_LAYOUT = 64
local ACTION_SCROLLBAR = 128
local BACKWARD_MASK = ACTION_SIZE_FIT + ACTION_LAYOUT
UIKit_Renderer_Cleaner.ACTION_SIZE_STATIC = ACTION_SIZE_STATIC
UIKit_Renderer_Cleaner.ACTION_SIZE_FIT = ACTION_SIZE_FIT
UIKit_Renderer_Cleaner.ACTION_SIZE_FILL = ACTION_SIZE_FILL
UIKit_Renderer_Cleaner.ACTION_POSITION_OFFSET = ACTION_POSITION_OFFSET
UIKit_Renderer_Cleaner.ACTION_ANCHOR = ACTION_ANCHOR
UIKit_Renderer_Cleaner.ACTION_POINT = ACTION_POINT
UIKit_Renderer_Cleaner.ACTION_LAYOUT = ACTION_LAYOUT
UIKit_Renderer_Cleaner.ACTION_SCROLLBAR = ACTION_SCROLLBAR


local washTimer = LazyTimer.New()
local cooldownTimer = LazyTimer.New()
washTimer:SetAction(function() UIKit_Renderer_Cleaner.Wash() end)
cooldownTimer:SetAction(function() UIKit_Renderer_Cleaner.onCooldown = false end)

function UIKit_Renderer_Cleaner.AddDirty(actionId, frame)
    local actions = frame[FIELD_ACTIONS] or 0
    if actions == 0 then
        dirtyCount = dirtyCount + 1
        dirty[dirtyCount] = frame
    end

    frame[FIELD_ACTIONS] = bor(actions, actionId)

    if band(actionId, BACKWARD_MASK) ~= 0 then
        hasBackwardActions = true
        UIKit_Renderer_Cleaner.requiresDependencyPass = true
    end

    if batchDepth > 0 then return end

    if not waitingForWash then
        waitingForWash = true
        washTimer:Start(0)
    end
end

function UIKit_Renderer_Cleaner.BeginBatch()
    batchDepth = batchDepth + 1
end

function UIKit_Renderer_Cleaner.EndBatch()
    batchDepth = batchDepth - 1
    if batchDepth < 0 then batchDepth = 0 end

    if batchDepth == 0 and dirtyCount > 0 and not waitingForWash then
        waitingForWash = true
        washTimer:Start(0)
    end
end

function UIKit_Renderer_Cleaner.IsBatching()
    return batchDepth > 0
end

local function ProcessForwardPass(frame, actions)
    if band(actions, ACTION_SIZE_STATIC) ~= 0 then Processor_SizeStatic(frame) end
    if band(actions, ACTION_SIZE_FILL) ~= 0 then Processor_SizeFill(frame) end
    if band(actions, ACTION_POSITION_OFFSET) ~= 0 then Processor_PositionOffset(frame) end
    if band(actions, ACTION_ANCHOR) ~= 0 then Processor_Anchor(frame) end
    if band(actions, ACTION_POINT) ~= 0 then Processor_Point(frame) end
end

local function ProcessBackwardPass(frame, actions)
    if band(actions, ACTION_SIZE_FIT) ~= 0 then Processor_SizeFit(frame) end
    if band(actions, ACTION_LAYOUT) ~= 0 then Processor_Layout(frame) end
end

--- Lays out every frame queued with AddDirty.
---
--- Takes the queue and empties it before processing: a frame queued while this runs (a size
--- change hook calling _Render mid-layout) goes into a fresh queue and gets its own wash next
--- frame, instead of being appended past this loop and lost for the rest of the session. On
--- cooldown, it tries again next frame rather than leaving the queue waiting forever.
function UIKit_Renderer_Cleaner.Wash()
    if dirtyCount == 0 then
        waitingForWash = false
        return
    end
    if UIKit_Renderer_Cleaner.onCooldown then
        waitingForWash = true
        washTimer:Start(0)
        return
    end

    UIKit_Renderer_Cleaner.onCooldown = true
    cooldownTimer:Start(0)
    waitingForWash = false

    local frames, count = dirty, dirtyCount
    local requiresDependencyPass = UIKit_Renderer_Cleaner.requiresDependencyPass
    local needsBackward = hasBackwardActions

    dirty, dirtyCount = {}, 0
    hasBackwardActions = false
    UIKit_Renderer_Cleaner.requiresDependencyPass = false

    -- Each frame's actions, read and cleared up front, so AddDirty during the passes queues it
    -- again rather than seeing it as already queued.
    local actionsOf = {}
    for i = 1, count do
        local frame = frames[i]
        actionsOf[i] = frame[FIELD_ACTIONS] or 0
        frame[FIELD_ACTIONS] = nil
    end

    -- PASS 1: Forward (top-down)
    for i = 1, count do
        ProcessForwardPass(frames[i], actionsOf[i])
    end

    -- PASS 1: Backward (bottom-up) - only if needed
    if needsBackward then
        for i = count, 1, -1 do
            ProcessBackwardPass(frames[i], actionsOf[i])
        end
    end

    -- PASS 2: Dependency resolution - only if needed
    if requiresDependencyPass then
        for i = 1, count do
            ProcessForwardPass(frames[i], actionsOf[i])
        end

        for i = count, 1, -1 do
            ProcessBackwardPass(frames[i], actionsOf[i])
        end
    end

    -- FINAL PASS: ScrollBar updates
    for i = 1, count do
        if band(actionsOf[i], ACTION_SCROLLBAR) ~= 0 then
            Processor_ScrollBar(frames[i])
        end
    end
end
