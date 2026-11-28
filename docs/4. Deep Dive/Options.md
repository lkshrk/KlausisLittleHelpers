# Deep Dive: Options

`/klh` opens KLH's own settings window. The sidebar has General, QoL, Helpers, 3rd Party and Profiles entries; empty client-specific categories are omitted. Feature pages appear under their category, with sectioned features sharing a page. The Blizzard Settings AddOns entry opens the same window after closing Settings.

`Core/Options.lua` builds the options tree, adds help and dependency messages, and registers profile callbacks and the Blizzard entry. Missing required addons disable the feature controls and prefix descriptions with the requirement. Profile switches apply live features, run their reset callbacks and request a refresh; other changed features require a reload.

`Core/OptionsModel.lua` translates the tree to sidebar entries and page controls. It honours the AceConfig-style group, toggle, range, select, input, execute, description and header fields used by KLH and AceDBOptions, including ordering, dynamic names and descriptions, hidden and disabled state, inherited handlers, get/set, values, range limits and confirmation. Disabled state is the OR of the control and each ancestor group, evaluated with the control's info. This deliberately differs from AceConfigDialog's nearest-declared value rule so a child cannot override Requires gating. The tree is not registered with an AceConfig library. Unsupported fields include `validate`, `dialogHidden`, `guiHidden`, `dialogDisabled`, `guiDisabled`, select style `radio`, `multiselect`, `color`, `keybinding` and `plugins`.

`Core/OptionsWindow.lua` lays out controls in a three-column grid. Ordinary controls span one column, while descriptions and headings span the full row; wider controls use the spans supplied by the model. Every set or execute refreshes existing widgets and schedules a rebuild on a later frame. Rebuilding waits while a slider is dragged, a menu is open, or an input has focus. Confirmation uses the widget kit's popup before a pending action or value is committed.

Sliders drag in `step` increments and use `bigStep` on the mouse wheel; their value boxes accept direct input. Inputs commit on Enter or the OK button.

`ns.NotifyOptionsChanged()` requests an update after changes made outside a control's setter. `ns.BuildOptionsTable` remains a pure builder; `ns.RegisterOptions()` sets up runtime callbacks and the Settings entry.
