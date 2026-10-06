# AX_Settings

A settings UI for World of Warcraft addons: its own movable window plus an **Options → AddOns**
panel (the same UI, moved between them), a tab sidebar, and widgets built from a declarative
schema. Embedded per addon (namespaced), like LibEditMode in namespaced mode.

Based on the settings UI of **WaypointUI by AdaptiveX**, licensed under the GNU General Public
License; this library is distributed under the same licence. See `NOTICE` and `LICENSE`.

## Embedding

Copy this folder and its toolkit, **AX_Modules**, into your addon (usually `libs\AX_Settings`
and `libs\AX_Modules`; any folders work, texture paths are found from each one's own location).
Load order in the `.toc`:

```
libs\AX_Modules\packages.xml        # toolkit, first
...                                # your setup: set env.AX_SettingsOptions here
libs\AX_Settings\AX_Settings.xml     # the framework (creates its frames while loading)
...                                # your schema file
```

Every file shares your addon's namespace (`local env = select(2, ...)`); modules are reached
through `env.AX_Modules:Import(...)` / `env.AX_Modules:Await(...)` (Await for modules that load later).

### Options

Set before `AX_Settings.xml` loads (checked by `Setting\Setting_Options.lua`):

```lua
env.AX_SettingsOptions = {
    prefix  = "MYADDON",          -- required: global frame names <prefix>_SettingFrame, _SettingWindow
    title   = "My Addon",         -- window title and Options -> AddOns category (default: prefix)
    storage = {                   -- required: where widget values live (schema `key`s)
        get = function(key) return MyAddonDB[key] end,
        set = function(key, value) MyAddonDB[key] = value end,
    },
    windowPosition = {            -- optional: remember where the window was dragged
        get = function() return MyAddonDB.windowPosition end,       -- { point, relativePoint, x, y }
        set = function(position) MyAddonDB.windowPosition = position end,
    },
    getSchema = function()        -- required: called once, when the UI is first shown
        return env.AX_Modules:Import("@\\Setting\\Schema").SCHEMA
    end,
}
```

`storage.get` is only called once the UI is shown, so saved variables can load after the
options are set.

### Opening the settings

```lua
local Setting = env.AX_Modules:Await("@\\Setting")
Setting.OpenSettingUI()   -- toggles the own window (hook it to a slash command / the addon drawer)
Setting.CloseWindow()     -- closes it if open
Setting.GetHost()         -- "window", "options" or nil (closed)
```

The Options → AddOns category is registered automatically when the addon loads. Blizzard's
Settings panel disables the spellbook, bags, collections etc. while it's open; use the own window
when the settings need drag & drop from those.

## Schema

The schema is a list of tabs; each tab has `children` (containers and widgets), containers have
`children` too. Widget types and helper structs:

```lua
local Setting_Enum   = env.AX_Modules:Import("@\\Setting\\Enum")    -- WidgetType, ImageType
local Setting_Define = env.AX_Modules:Import("@\\Setting\\Define")  -- Descriptor, TitleInfo
```

A complete, commented example using every type and field: `Examples\Schema.example.lua` (not
loaded by the library).

### Fields every entry can use

| Field | Type | Meaning |
|---|---|---|
| `widgetType` | `Setting_Enum.WidgetType.*` | required |
| `widgetName` | string | label (tab button text, container title, widget name) |
| `widgetDescription` | `Setting_Define.Descriptor{ description, imagePath, imageType }` | text (and optional image) under the name; widgets only. `description` can be a function returning the text: re-read on every refresh, so it can follow other settings |
| `widgetTransparent` | boolean | no background box (not for Title) |
| `indent` | number | indent level; widgets only |
| `showWhen` | `function(widget) -> boolean` | re-checked on every refresh |
| `disableWhen` | `function(widget) -> boolean` | disables the control; widgets with a control |
| `children` | table | tabs and containers |

### Per type

| Type | Fields | Stored value (`key`) | `set` called as |
|---|---|---|---|
| `Tab` | `widgetTab_isFooter` (bottom of the sidebar) | — | — |
| `Title` | `widgetTitle_info = Setting_Define.TitleInfo{ imagePath, text, subtext }` (required) | — | — |
| `Container` | `widgetContainer_isNested` (sub-container look) | — | — |
| `Text` | name and description only | — | — |
| `Range` | `widgetRange_min`, `_max`, `_step` (required; numbers or functions, re-read on refresh when both min and max are functions), `widgetRange_textFormatting` (`"%s%%"`) or `widgetRange_textFormattingFunc(value)` | number (`key` required) | `set(slider, value, userInput)` |
| `Button` | `widgetButton_text` (required), `widgetButton_refreshOnClick` | — | `set(button)` on click |
| `CheckButton` | — | boolean | `set(widget, checked)` |
| `SelectionMenu` | `widgetSelectionMenu_data` (list of labels, or a function returning it) | index into the list | `set(menu, index)` |
| `ColorInput` | — | `{ r, g, b }` (0–1) | `set(colorInput, color)` |
| `Input` | `widgetInput_placeholder` | string | `set(input, text)` (typing only) |
| `Custom` | `widgetCustom_build(parent, tab) -> frame` (required) | — | — |

`key` + `set`: a widget with a `key` reads its value through `storage.get(key)` and writes it
with `storage.set(key, value)` when the user changes it, then calls `set` (if given) for side
effects. A widget without a `key` just calls `set`.

### Custom widgets

`widgetCustom_build(parent, tab)` builds hand-made UI (a UIKit frame, already parented) inside a
tab and returns it. If the frame has `OnSettingRefresh`, it's called on every settings refresh.
After changing its own size, call `tab:_Render()` so the tab lays out again.

## Refreshing

`Setting.Refresh` (CallbackRegistry) makes every widget re-read its value and re-check
`showWhen` / `disableWhen`. It fires after any widget changes a value; trigger it yourself after
changing stored values elsewhere:

```lua
local CallbackRegistry = env.AX_Modules:Import("ax_modules\\callback-registry")
CallbackRegistry.Trigger("Setting.Refresh")
```

`Setting.HostChanged` fires with `"window"`, `"options"` or `nil` when the settings move or close.

## List tabs

A tab whose sidebar entry is a list of selectable items (profiles, groups, ...), each opening the
tab's page for that item. Call it from the tab's Custom widget builder:

```lua
widgetCustom_build = function(parent, tab)
    local page = BuildMyPage(parent)
    page.Nav = Setting.AttachListNav(tab, {
        sections = {
            { title = "Pinned", visible = 2, getItems = GetPinnedItems },
            { title = "Yours", newButton = { text = "+ New", onClick = CreateItem }, getItems = GetItems },
        },
        getSelected = function() return page.selectedId end,
        onSelect    = function(id) page.selectedId = id; page:Show(id) end,
    })
    return page
end
```

- `getItems()` returns `{ { id, title, left, right }, ... }`: a card with a title and a detail line
  (text on the left and on the right).
- `visible`: cards shown before the section scrolls; leave it out on the last section to fill the
  rest of the sidebar.
- The tab's own button becomes the first section's header; later sections get their own header.
- `nav:Refresh()` after items or the selection change; `nav:Select(id)` selects from code
  (calls `onSelect`, opens the tab, refreshes).
- The list fills the sidebar below the tab's button, so the list tab should be the last tab above
  the footer tabs.

## Also available

```lua
local Setting_Preload = env.AX_Modules:Import("@\\Setting\\Preload")
local frame = _G[Setting_Preload.FRAME_NAME]

frame.Prompt:Open({                                 -- confirmation dialog
    text = "Delete %s?",
    options = { { text = "Delete", callback = DoDelete }, { text = "Cancel" } },
    hideOnEscape = true,
    timeout = 10,
}, itemName)                                        -- formatted into text

frame.SelectionMenu                                 -- the shared dropdown list (for custom UI)
Setting_Preload.UIDef                               -- the library's textures (tab buttons, containers, widget background)
```

The widget templates in `Setting\Setting_Widgets.lua` (module `@\\Setting\\Widgets`: `Container`, `ContainerWithTitle`,
`ElementInput`, `ElementButton`, `ElementSelectionMenu`, ...) can be used in custom pages, and
the toolkit (UIKit, `uic-common`) is available to the addon too.

## Limits

- One settings UI per addon (frames are created once, when the library loads).
- The list tab has to be the last tab above the footer.
