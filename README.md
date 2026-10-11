# RL: Radial Menu

Radial menus for your spells, items, toys, mounts and markers, in the style of the game's ping
wheel. **Hold a key, flick the mouse, release.**

![A radial menu: flick toward an action and release to use it](Media/radial-menu-demo.gif)

- One keybind per menu, as many menus as you like.
- Works in combat.
- Built-in menus that fill themselves: quest items, hearthstones, trinkets, season teleports,
  markers, specializations, talent loadouts and professions.
- A **quick action** for a tap: press and release without moving. The action fires without the
  menu ever appearing.

## Getting started

1. Type `/radial` (or `/radialmenu`, `/rm`), or open it from the addon drawer on the minimap.
2. On the **Menus** tab, click **+ New**.
3. Click **Keybind** and press the key (or combination) you want to hold.
4. Add actions: click **+** on the menu and search, or drag spells, items, toys, macros and
   mounts straight from your spellbook, bags or collections onto it.

![Building a menu: dragging spells onto it and searching in Add Action](Media/menu-editing.gif)

Then hold your key in the game, move the mouse toward an action and let go.

## Using a menu

- **Pick an action:** hold the keybind, move the mouse toward the action, release.
- **Cancel:** press Escape, right-click (Right-Click to Cancel, on by default), or move back to the
  center (the X) and release.
- **Quick action:** tap the keybind without moving the mouse. Release before the **Reveal
  Delay** and the menu never even shows. The quick action is the action in the menu's center:
  drag any action there (an action from the wheel is copied, so it stays there too), drag it out
  onto the wheel, or double-click the center to cycle Close Menu, Last Used Action and First
  Action.

![A tap fires the quick action without the menu appearing](Media/quick-action.gif)

**Relaxed style** (Menu Style, in the settings): press the keybind and the menu opens and stays
open. Click an action to use it. Clicking the center uses the quick action, like releasing there
in Quick: until you move the mouse away, then it closes the menu. Escape, the keybind again or
right-click (Right-Click to Cancel) also close it.

## What a menu can hold

| Action | | Retail | Forever |
|---|---|:---:|:---:|
| Spells | including pet abilities, and spells from flyouts such as portals and dungeon teleports (Forever: a specific rank, or always your highest rank) | ✓ | ✓ |
| Items | consumables show how many you have; hidden while you have none | ✓ | ✓ |
| Toys, Mounts, Battle Pets | from your collections, plus a random favorite mount or pet | ✓ | ✓ |
| Macros | your account and character macros | ✓ | ✓ |
| Emotes | | ✓ | ✓ |
| Pet Commands | Attack, Follow, Stay, stances, ...; hidden while you have no pet | ✓ | ✓ |
| Target Markers | Skull, Cross, ... on your target, and Clear | ✓ | ✓ |
| World Markers | placed under the mouse, or with a targeting circle; and Clear | ✓ | ✓ |
| Equipped Slot | uses whatever is in that slot (trinket 1, ...); hidden while it has no use effect | ✓ | ✓ |
| Close Menu | closes the menu without using anything | ✓ | ✓ |
| Last Used Action | uses whatever the menu used last, from any wedge (the quick action can be Last Used too) | ✓ | ✓ |
| First Action | uses whatever the menu's first action is on this character (a submenu for each character or class first: a different action on each) | ✓ | ✓ |
| Zone Ability, Extra Action | follow the game's buttons; hidden while there's none | ✓ | — |
| Housing | Teleport Home to Founder's Point or Razorwind Shores (hidden while you don't own a house there), and Return | ✓ | — |
| Specializations | switch to another spec of your class; hidden while it's your current one | ✓ | — |
| Talent Loadouts | load a saved build for your current spec; hidden while it's the active one | ✓ | — |
| Action Bars | one of your action bars (1–8): in game it becomes the bar's buttons, firing whatever is on them. Action Bar 1 follows its page (stances, forms, stealth, Shift+1–6). Hidden while the bar is empty or turned off | ✓ | ✓ |
| Submenus | another of your menus inside this one (below) | ✓ | ✓ |

Actions that have nothing to fire right now are left out of the menu until they're usable again:
an item you're out of, a pet ability with no pet, another class's spell. In the settings preview,
the eye in the top corner leaves them out too, so the preview matches the menu in game.

The icons show what the game shows on your action bars:

- Cooldowns and charges.
- Blue without enough resources, grey while unusable.
- Red when your target is out of range (like Blizzard's Cooldown Manager).
- A glow when the spell procs.
- A highlight on your active stance or form.

**Submenus:** a menu can contain another menu. By default it takes one slot. While holding your
keybind, **scroll the mouse wheel** over it to cycle through its actions, and release on the one
shown. Double-click it in the settings to **spread** its actions into the menu instead.

## Built-in menus

These fill themselves and stay up to date. Give them a keybind and rearrange them as you like.
Remove what you don't need with the X: it stays out as the menu refills, and the menu's page lists
what you removed, to restore it.

| Menu | What's in it | Retail | Forever |
|---|---|:---:|:---:|
| Consumables | the four menus below as submenus: one wedge each, scroll with the mouse wheel | ✓ | ✓ |
| Flasks & Elixirs | flasks, phials and elixirs in your bags | ✓ | ✓ |
| Food & Drink | food and drink in your bags | ✓ | ✓ |
| Hearthstones | your Hearthstone, the hearthstone toys you own, Teleport Home to your houses, and Return | ✓ | — |
| Other Consumables | bandages, scrolls, explosives & devices, item enhancements and Vantus runes in your bags | ✓ | ✓ |
| Potions | potions and Healthstones in your bags | ✓ | ✓ |
| Professions | your professions (opens their window) and their extra spells: Disenchant, Prospecting, Survey, Fishing… | ✓ | ✓ |
| Quest Items | usable quest items from your quest log and bags (Forever: from your bags) | ✓ | ✓ |
| Season Teleports | the current Mythic+ season's dungeon teleports you've earned | ✓ | — |
| Specializations | the specs of your class you can switch to | ✓ | — |
| Talent Loadouts | your current spec's saved builds, except the active one | ✓ | — |
| Target Markers | all eight target markers, and Clear | ✓ | ✓ |
| Trinkets & On-Use | every equipped item with a use effect | ✓ | ✓ |
| World Markers | all eight world markers, and Clear | ✓ | ✓ |
| Zone and Extra | the Zone Ability and the Extra Action Button | ✓ | — |

## Sharing menus

**Share:** open one of your menus and find **Share Menu** under its settings. Click the string,
press Ctrl+C, and send it to a friend.

- Its submenus come along. A built-in submenu links to the importer's own built-in menu.
- Macros come along with their text. The box lists which ones, so nothing is shared by surprise.
- Left out: keybinds, battle pets (tied to your account; a random favorite still works), macros
  you've deleted, and submenus with nothing left in them. The box lists what's left out and why.

**Import:** click **Import** under the menu list and paste the string (Ctrl+V). Before you import,
the page shows:

- **Menus:** each menu and its action count. A menu is renamed "Name (2)" when you already
  have one with that name, and the page says so. Actions that can't be added here are skipped,
  and the page says which and why.
- **New Macros:** every macro the import creates, with its text, so you can check what it does.
  They go into your account macros. A macro you already have (same name and text) is reused.

Importing only adds new menus; nothing you have is replaced. Strings only import into the same
game (Retail or WoW Forever), and not in combat.

## Settings

Everything is in `/radial` (also under Options → AddOns).

![Open Menus At, a fixed position in Edit Mode, and the cursor guide](Media/menu-positions.gif)

- **Open Menus At:** at the mouse cursor, or at a **Fixed Position** you place in Edit Mode
  (saved per Edit Mode layout).
- **Select From** (fixed position): pick by the direction you move from where you pressed the
  key, or by where the mouse is over the menu itself.
- **Show Cursor Guide** (fixed position): a faint outline of the menu at the cursor, so you can
  see the directions while the menu is elsewhere.
- **Menu Size** and **Show Action Names**.
- **Menu Behavior:** Menu Style (Quick or Relaxed), Reveal Delay (Quick), Distance to Select,
  Distance to Cancel Quick Action, Right-Click to Cancel, and how world markers are placed.
- **Per menu:** name, keybind, quick action, whether it's on all your characters, the
  characters of your class or just this one, and its share string.

## Game versions

- **Retail** (Midnight): everything above.
- **WoW Forever:** loads and works, without the parts marked — in the tables above.

## Credits and licence

RL: Radial Menu is free software under the **GNU General Public License v3** (see `LICENSE` and
`NOTICE`).

- The settings window and its UI toolkit (`libs\AX_Settings`, `libs\AX_Modules`) are based on
  **WaypointUI** by **AdaptiveX** (GPLv3).
- Fixed position via **LibEditMode** by p3lim.
- The menu's look follows Blizzard's ping wheel.
