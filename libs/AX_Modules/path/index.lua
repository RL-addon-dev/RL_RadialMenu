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

-- Art variant for this game version: WoW Forever (interface 1.6x) has its own recoloured art in
-- a "forever" folder next to the default files; every other client uses the defaults. Worked out
-- here because the toolkit loads before the addon's own game version detection.
do
    local interface = select(4, GetBuildInfo())
    Path.Skin = (interface >= 16000 and interface < 20000) and "forever" or nil
end

--- `folder`\`file`, or `folder`\<skin>\`file` when this game version has its own art (Path.Skin).
--- Only for files that have a variant in every skin folder.
function Path.Skinned(folder, file)
    if Path.Skin then return folder .. "\\" .. Path.Skin .. "\\" .. file end
    return folder .. "\\" .. file
end
