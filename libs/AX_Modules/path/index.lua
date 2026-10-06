local addonName, env = ...
local Path = env.AX_Modules:New("ax_modules\\path")

-- The addon's folder.
Path.Root = "Interface\\AddOns\\" .. addonName

-- This toolkit's own folder (AX_Modules), wherever the addon keeps it: worked out from this
-- file's own path (…\<toolkit>\path\index.lua). Falls back to the usual place,
-- <addon>\libs\AX_Modules, if the path can't be read.
do
    local source = debugstack and debugstack(1, 1, 0) or ""
    local folder = source:match("(Interface[/\\][Aa][Dd][Dd][Oo][Nn][Ss][/\\][^%.\"]-)[/\\]path[/\\]index%.lua")
    Path.Modules = folder and (folder:gsub("/", "\\")) or (Path.Root .. "\\libs\\AX_Modules")
end
