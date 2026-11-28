# Deep Dive: Farm Tracker

## Overview

Farm Tracker shows a movable text watcher for fishing and farming on retail and Forever. Only one session runs at a time. Its area history is stored in AceDB global settings and shared by all characters.

## Files

- **`Modules/FarmTrackerLogic.lua`**: `ns.FarmLogic`, the pure session, history, sorting and display calculations.
- **`Modules/FarmTracker.lua`**: `ns.FarmTracker`, events, area persistence, watcher, commands and options.
- **`Core/UI.lua`**: shared number and money formatting and watcher widgets.
- **`.tools/tests/farmlogic_test.lua`**, **`.tools/tests/farmtracker_test.lua`**: logic and event integration tests.

## Sessions and history

A Fishing channel cast (spell IDs 7620, 131474, 131476 or 131490, or the spellbook Fishing ID) starts fishing, as does fishing loot if a session is not already active in that fishing area. Further casts and fishing loot refresh the idle timer. Fishing ends on a zone or subzone change, or after the configured idle period without a cast (default 10 minutes). Fishing tracks only fishing loot. Its area key combines the zone and subzone.

`/klh farm` or the minimap menu's **Toggle farming** starts or stops manual farming. Farming records non-fishing loot windows and the coin you loot. A zone change ends the old session and starts another for the new zone; subzone changes do not. The first session wins: while farming, Fishing casts and fished loot are ignored; while fishing, `/klh farm` and the menu entry refuse to start farming and say so. The watcher's `x` stops either session. Fishing casts are recognised by spell ID (7620, 131474 and the Fishing spell found in the spellbook under the Fishing profession), the way Fishing Buddy's LibFishing and EasyFishing do.

Loot is read only during a session or for fished loot. Loot opened from bag items is skipped (an `Item-` source GUID or `LOOT_OPENED` isFromItem). A farming source counts once per session; fishing does not deduplicate sources because a pool keeps its GUID. Secret GUIDs share one anonymous source. Loot windows count distinct source GUIDs as attempts; each item records its quantity and number of distinct sources. If source information is unavailable, each window and item falls back to one source. Session counts and area history are updated together. Time is merged into area history on stopping, changing sessions or logging out; the running view includes unmerged time.

## Watcher

Farming gold comes from `CHAT_MSG_MONEY`, which fires for your own coin loot ("You loot ...") and for a group share of a corpse someone else looted ("Your share of the loot is ..."), which opens no loot window of your own. `FarmLogic.LootMoney` matches the text against the client's own global strings (`YOU_LOOT_MONEY`, `LOOT_MONEY_SPLIT` and their `_GUILD` variants, whose guild bank part is left out) and reads the amount with `GOLD_AMOUNT`, `SILVER_AMOUNT` and `COPPER_AMOUNT`, expanding the `|1` and `|4` grammar codes some locales use and ignoring thousands separators. Another player's `LOOT_MONEY` line is rejected. Vendor sales, quest rewards, mail and repairs change money without this event, so they never count. Coin goes to the running farming session's current area; coin from a bag item or fished loot, secret message text and anything during a fishing session is skipped.

The watcher shows the summary as two columns: the yellow labels (Skill when fishing and known, Elapsed, Gold when farming, Totals) on the left and every value starting at the same x, the widest label plus a small gap. Below a thin divider (1 px, label yellow at 40% alpha, only when there are item rows) come the item rows: the name in its quality colour on the left, then right-justified columns `(`, session count, ` : `, session %, `, `, area count, ` : `, area %, `)`. Each column is as wide as its widest cell, so digits and % signs line up across rows; the frame is the widest name plus a gap plus the columns, padded on both sides. `FarmLogic.Lines` returns each row as a name and a list of cells; with `showPercent = false` in the view the percent columns and their ` : ` separators are left out. Fishing totals count items; fishing percentages are each item's share of all items. Farming totals count loot sources; farming percentages are sources dropping the item divided by all sources. Each item row shows session count and percentage followed by area count and percentage. Rows sort by descending quality, session count and area count, then name and item ID. Labels are yellow, skill green, item names use quality colours and other values use the normal text colour. The watcher can be dragged; its position is stored in the current profile.

## Options and testing

The Helpers tab offers **Fishing idle minutes** (1-60) and **Reset this area**, which confirms before clearing the active area's history and restarting its session. This reset is unavailable without an active session. **Reset all areas** confirms before clearing all area history shared across characters; it restarts an active session in the same area, or simply clears history if no session is running. Other global data is unchanged. Automated tests cover the pure calculations and the event-driven tracker. In game, check fishing casts and loot, zone transitions, manual farming, the stop button, area resets and shared history across characters.

The watcher can pause and resume the current session without counting time, loot or fishing failures while paused. Changing areas while paused ends the session. Fishing failures show session and area counts for the localized escaped and not-hooked messages; repeated messages for one recognized cast count once. Message and channel event ordering has not been verified in game.
