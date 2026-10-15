--[[
    Performance log: /rm perf toggles a line in chat every 5 seconds with what the addon cost in
    that time, to find what's heavy while playing (and for testers to send):

        cpu      the game's addon profiler: recent average per frame, and the peak (Retail)
        mem      memory now, and how much it grew in those 5 s (temporary data not yet collected)
        updates  Ring_Auto's background updates: how many, their time, built-in menus refilled
        events   the events that asked for them, most first
        ui       the settings' per-frame work: the preview's per-frame script (frames, time),
                 UIKit layout passes (how many, time), animations running now
        open     what's on screen that runs every frame (a menu, the settings)

    When UIKit frames asked for layout, two more lines: the frames that asked most (with their
    size), and the calls that led to the first one (file:line, newest first). A frame asking every
    pass is a layout loop.

    Off by default and costs nothing then: no timer, Ring_Auto and the preview only count while
    `enabled`, and UIKit's functions are only wrapped while it's on.
]]

local addonName, env = ...
local UIAnim = env.AX_Modules:Import("ax_modules\\ui-anim")
local UIKit_Cleaner = env.AX_Modules:Import("ax_modules\\ui-kit\\renderer\\cleaner")
local UIKit_Scanner = env.AX_Modules:Import("ax_modules\\ui-kit\\ui\\scanner")
local Perf = env.AX_Modules:New("@\\Perf")
local Setting = env.AX_Modules:Await("@\\Setting")

local INTERVAL = 5     -- s between lines
local TOP_EVENTS = 4   -- events named per line
local TOP_SCANS = 3    -- frames named per rescans line
local NAME_LENGTH = 70 -- frame names are shortened to their end

Perf.enabled = false

local ticker, lastMemory



-- Counters (reset after every line)

local eventCounts = {}
local updates, updateMs, refills
local previewFrames, previewMs
local layouts, layoutMs
local scanCounts, scanSizes, scanCallers = {}, {}, {}

local function ResetCounters()
    wipe(eventCounts)
    wipe(scanCounts)
    wipe(scanSizes)
    wipe(scanCallers)
    updates, updateMs, refills = 0, 0, 0
    previewFrames, previewMs = 0, 0
    layouts, layoutMs = 0, 0
end
ResetCounters()

--- An event that asked Ring_Auto for an update (while enabled).
function Perf.CountEvent(event)
    eventCounts[event] = (eventCounts[event] or 0) + 1
end

--- One Ring_Auto update: its time in ms and how many built-in menus it refilled (while enabled).
function Perf.CountUpdate(ms, refilled)
    updates = updates + 1
    updateMs = updateMs + ms
    refills = refills + refilled
end

--- One run of the settings preview's per-frame script (while enabled).
function Perf.CountPreviewFrame(ms)
    previewFrames = previewFrames + 1
    previewMs = previewMs + ms
end



-- UIKit, wrapped while the log is on: its timer and scans call these through the module tables,
-- so the wrappers are what run.

-- Layout passes: how many, and their time.
local originalWash = UIKit_Cleaner.Wash
local function TimedWash(...)
    local start = debugprofilestop()
    originalWash(...)
    layouts = layouts + 1
    layoutMs = layoutMs + debugprofilestop() - start
end

-- What asks for them: each frame's re-scans, its size at the last one, and (once per line) the
-- calls that led there.
local originalScan = UIKit_Scanner.ScanFrame
local function CountedScan(frame, ...)
    local name = frame.GetDebugName and frame:GetDebugName() or tostring(frame)
    if #name > NAME_LENGTH then name = "…" .. name:sub(1 - NAME_LENGTH) end
    scanCounts[name] = (scanCounts[name] or 0) + 1
    local width, height = frame:GetSize()
    scanSizes[name] = format("%.2fx%.2f", width or 0, height or 0)
    if not scanCallers[name] then
        local lines = {}
        for file, line in debugstack(2, 10, 0):gmatch("([%w_%-]+%.lua)\"?%]?:(%d+)") do
            lines[#lines + 1] = file .. ":" .. line
        end
        scanCallers[name] = table.concat(lines, " < ")
    end
    return originalScan(frame, ...)
end



-- The line

--- `counts` ({ [name] = count }) as { name, count } pairs, most first, at most `limit`.
local function Top(counts, limit)
    local list = {}
    for name, count in pairs(counts) do list[#list + 1] = { name, count } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = #list, limit + 1, -1 do list[i] = nil end
    return list
end

local function CpuText()
    local profiler = C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric
    local metric = Enum.AddOnProfilerMetric
    if not (profiler and metric) then return nil end
    return format("cpu %.3f ms/frame (peak %.1f)", profiler(addonName, metric.RecentAverageTime) or 0,
        profiler(addonName, metric.PeakTime) or 0)
end

local function EventsText()
    local parts = {}
    for i, entry in ipairs(Top(eventCounts, TOP_EVENTS)) do parts[i] = entry[1] .. " " .. entry[2] end
    return "events: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
end

local function OpenText()
    local open = {}
    local view = _G["RLRM_RingView"] -- the in-game menu (Ring_View)
    if view and view:IsShown() then open[#open + 1] = "menu" end
    if Setting.GetHost and Setting.GetHost() then open[#open + 1] = "settings" end
    return "open: " .. (#open > 0 and table.concat(open, ", ") or "none")
end

--- The rescans line and its caller line, or nil when no frame asked for layout.
local function ScansText()
    local top = Top(scanCounts, TOP_SCANS)
    if #top == 0 then return nil end
    local parts = {}
    for i, entry in ipairs(top) do parts[i] = format("%s %d (%s)", entry[1], entry[2], scanSizes[entry[1]]) end
    return "rescans: " .. table.concat(parts, ", "), "rescan caller: " .. (scanCallers[top[1][1]] or "?")
end

local function Report()
    UpdateAddOnMemoryUsage()
    local memory = GetAddOnMemoryUsage(addonName) / 1024
    local parts = {}
    parts[#parts + 1] = CpuText()
    parts[#parts + 1] = format("mem %.1f MB (%+.1f)", memory, lastMemory and memory - lastMemory or 0)
    parts[#parts + 1] = format("updates %d (%.1f ms, refills %d)", updates, updateMs, refills)
    parts[#parts + 1] = EventsText()
    parts[#parts + 1] = format("ui: preview %d (%.1f ms), layouts %d (%.1f ms), anims %d",
        previewFrames, previewMs, layouts, layoutMs, UIAnim.GetActiveCount())
    parts[#parts + 1] = OpenText()
    env.Print(table.concat(parts, " | "))

    local scans, caller = ScansText()
    if scans then
        env.Print(scans)
        env.Print(caller)
    end

    lastMemory = memory
    ResetCounters()
end



--- /rm perf: turns the log on or off.
function Perf.Toggle()
    Perf.enabled = not Perf.enabled
    if Perf.enabled then
        ResetCounters()
        lastMemory = nil
        UIKit_Cleaner.Wash = TimedWash
        UIKit_Scanner.ScanFrame = CountedScan
        ticker = C_Timer.NewTicker(INTERVAL, Report)
        env.Print(format("performance log on (every %d s; /rm perf to stop)", INTERVAL))
    else
        UIKit_Cleaner.Wash = originalWash
        UIKit_Scanner.ScanFrame = originalScan
        if ticker then ticker:Cancel() end
        ticker = nil
        env.Print("performance log off")
    end
end
