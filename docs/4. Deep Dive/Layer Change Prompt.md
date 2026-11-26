# Deep Dive: Layer Change Prompt

## Overview

Layer Change Prompt (feature key `LayerPrompt`, Forever only, QoL tab, section "Interface", `alwaysOn`) moves Blizzard's layer change prompt to a spot the player chooses and keeps it above other frames. The prompt is `ShardTransferImminentFrame` from `Blizzard_SocialToast`: it shows on `SHARD_TRANSFER_IMMINENT` with a countdown, and clicking it opens a popup whose button calls `C_PlayerInteractionManager.ShardTransferConfirm()` to change layer at once. Retail has no such frame.

## Why it exists

Blizzard anchors the prompt in its `OnLoad` 30/55 px above `ChatAlertFrame`, which hangs off `ChatFrame1ButtonFrame`, at strata LOW. Chat addons break that chain: TustUI (`Tust_EUI/Chat/TustEUI_Chat_Appearance.lua`, `SuppressBlizzardChatControls`, hooked on `FCF_SetButtonSide`) re-anchors `ChatFrame1ButtonFrame` with one point 90000 px below the chat unless its chat menu is active. The prompt is then shown but has no position (`GetLeft()` is nil), so it never appears. A LOW-strata prompt can also sit under MEDIUM-strata chat panels.

## Files

- **`Modules/LayerPrompt.lua`** (`ns.LayerPrompt`):
  - a holder frame on UIParent (250x50, strata DIALOG), placed from `pos` or at `TOP` 0/-320 (below Blizzard's confirm StaticPopup at `TOP` -135, which shares the DIALOG strata);
  - `LP.Apply()` anchors the prompt's `TOP` to the holder's `TOP` (it grows downward) and sets the prompt and `ShardTransferImminentMinimizeButton` to strata DIALOG; the minimize button follows because Blizzard anchors it to the prompt;
  - an `OnShow` hook on the prompt runs `Apply` every time it shows;
  - at `PLAYER_LOGIN` the prompt usually exists; if not, a watcher waits for `ADDON_LOADED` of `Blizzard_SocialToast`.
- Tests: `.tools/tests/layerprompt_test.lua` (the watcher path, and a prompt that already exists at login: anchored at once, hooked once).

## Options

- **Move prompt / Lock position**: shows the holder as a labelled box; drag it (the drop point is saved as `pos`), then lock it here or right-click the box. A profile swap or reset locks it.
- **Reset position**: clears `pos` and returns to the top centre.

## Testing in game

`/run ShardTransferImminentFrame:Start()` shows the prompt without a pending transfer (no countdown, `SHARD_TRANSFER_ANYTIME` text); do not click it, since the popup can change layer. `/run ShardTransferImminentFrame:Hide()` closes it.
