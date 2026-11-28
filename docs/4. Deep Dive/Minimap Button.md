# Deep Dive: Minimap Button

## Overview

`Modules/MinimapButton.lua` adds a minimap button on retail and Forever. Left-click opens settings; right-click opens the helpers menu; drag moves the button. The addon compartment entry offers the same clicks.

## Files

- **`Modules/MinimapButton.lua`**: LibDataBroker launcher, LibDBIcon registration, tooltip, click handlers and options.
- **`Core/Core.lua`**: validates feature launchers and supplies `ns.Launchers()`.
- **`KlausisLittleHelpers.toc`**: addon compartment callbacks.
- **`.tools/tests/minimapbutton_test.lua`**: button, menu, settings and compartment tests.

## Implementation

The always-on `MinimapButton` feature registers a LibDataBroker-1.1 launcher named `KlausisLittleHelpers` with the Mechanical Squirrel icon, then registers it with LibDBIcon-1.0. Both libraries are looked up silently through LibStub; if either is missing, the feature does nothing. EllesmereUI's minimap module can collect LibDBIcon buttons into its flyout.

The right-click menu uses `ns.Launchers()`, which returns launchers of features whose enable succeeded, in registration order. A feature supplies `launcher = { text = ..., onClick = ... }`. Farm Tracker's **Toggle farming** starts or stops manual farming; Turn-in Route plans all sources, like left-clicking its map button. If no launchers are available, the menu shows "No helpers available". The compartment menu anchors to `AddonCompartmentFrame`.

## Options and settings

The button has no settings and is always shown, like most addons' buttons; a `hide` flag left from an older version is cleared on load and on profile switches. LibDBIcon stores `minimapPos` in the feature's profile settings. On a profile switch, copy or reset, `onReset` refreshes the icon with the current settings.

## Testing in game

- Left-click the button and compartment entry to open settings; right-click each to open the helpers menu.
- Drag the button, hide and show it in QoL, then switch profiles to check its visibility and position.
- Check that only running helpers appear in the menu and that each opens its helper.
