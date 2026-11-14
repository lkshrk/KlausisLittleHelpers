# LKS_UI agent guide

LKS_UI is a companion addon for EllesmereUI (EUI). It holds changes the EUI maintainer declined upstream, as opt-in features. It loads on retail (12.x) and WoW Forever (16001), the same clients as EUI.

## Layout

- `LKS_UI.toc`: load manifest. The repository root is the addon folder (`package-as: LKS_UI`).
- `Core/LKS_UI_Core.lua`: namespace (`ns`, also `_G.LKS_UI`), settings, feature registry, `/lks`.
- `Core/LKS_UI_Options.lua`: registers the "LKS UI" sidebar section with `EllesmereUI.RegisterPlugin`.
- `Modules/<Feature>.lua`: one file per feature, listed in the TOC after `Core/`.
- `scripts/`: check, sync, error reader, UI source lookup, release. `.tools/`: their Lua helpers (skipped by the guardrails).

## Adding a feature

```lua
if EUI_CLIENT_BLOCKED then return end

local _, ns = ...

ns.RegisterFeature({
    key = "PasteCommands",
    title = "Paste Commands",
    description = "Adds /euipaste to run several pasted addon commands.",
    clients = nil,              -- "retail" or "forever" to load on one client only
    defaults = { showButton = true },
    enable = function(settings) end,
    buildOptions = function(W, parent, y, settings) return y end,  -- optional; gets its own sidebar row
})
```

- Every feature starts off. `enable` runs once at `PLAYER_LOGIN`, only when the feature is on; toggling asks for a reload. Nothing runs, registers or hooks while a feature is off.
- Read settings through the `settings` table or `ns.GetSettings(key)`; never cache `db.profile`. Settings live in the active EUI profile (`EllesmereUIDB.profiles[<p>].addons.LKS_UI`) through `EllesmereUI.Lite.NewDB`.
- A feature ported from a declined EUI PR keeps EUI's acceptance criteria (`~/Dev/EllesmereUI/.github/CONTRIBUTING.md`), so it can still go upstream later.
- Use only the public plugin API (`~/Dev/EllesmereUI/PLUGINS_API.md`) and public `EllesmereUI.*` helpers. Never read fields starting with `_`, never hook or replace EUI functions, never add pages to EUI's own modules.

## Code style (EllesmereUI's)

- Lua 5.1 only. No `goto`, no `::labels::`.
- ASCII only in code, comments and strings: no em dashes, no curly quotes.
- Line 1 of every addon Lua file is `if EUI_CLIENT_BLOCKED then return end`.
- Match the surrounding code. Before building an options widget (row, slider, swatch, cog popup), find the nearest existing example in EUI's options files and copy its shape.
- House UI systems, not Blizzard defaults: plain-text tooltips via `EllesmereUI.ShowWidgetTooltip` / `HideWidgetTooltip`; confirmations via `EllesmereUI:ShowConfirmPopup`, never `StaticPopup_Show`.
- Options pages use two-slot rows (`W:DualRow`). Fill slots left to right with no gaps; never pass nil as the right slot (use `EllesmereUI.BlankRowCfg()`, a fresh one per call); only the last row of a section may have an empty slot.
- `buildPage` also runs in the search pre-build pass with stub widgets: skip side effects while `EllesmereUI.IsSearchPrebuild()` is true.
- EUI's AGENTS.md rules apply here too: combat deferral through `EllesmereUI.CombatQueue.Defer`, no Forever-missing globals (use the `C_` form), no compare/index/arithmetic on secret values, no protected frame writes in combat.
- Almost no comments; one line at most, only for a non-obvious why.

## API and game data

- Blizzard UI source: `scripts/ui-source.sh update` clones https://github.com/Gethe/wow-ui-source (branches `live` and `forever`) into `~/.local/share/wow/`. Look an API up with `scripts/ui-source.sh grep 'C_Item\.GetItemInfo' [live|forever]` before using it, and check the Forever branch for anything that must run there.
- Game data (spells, items, DB2 tables): https://wago.tools (`/db2/<Table>`, CSV via `/db2/<Table>/csv?build=<build>`).
- EUI source: `~/Dev/EllesmereUI`.

## Validate, test, release

```sh
scripts/check.sh                      # luac 5.1 compile, TOC coverage, luacheck, EUI guardrails
scripts/sync.sh retail|forever|all [--dry-run]   # copy into the live AddOns folders, then /reload
scripts/errors.sh [retail|forever] [pattern] [--all-sessions]   # !BugGrabber errors, default pattern LKS_UI
```

- `check.sh` runs `~/Dev/EllesmereUI/.tools/guardrails.py` from a copy in `.tools/` against the repository's empty root commit, so every file is checked in full. CI does the same with a sparse EUI checkout.
- Hooks: run `lefthook install` once per clone. Pre-commit checks staged files (gitleaks, luac, luacheck, TOC, shellcheck, YAML, actionlint); pre-push runs `scripts/check.sh`. Never skip them with `--no-verify`.
- Commit only when `scripts/check.sh` passes. Push only when asked.
- Sync only the flavour the change targets, preview with `--dry-run` first, then ask the user to `/reload`, or to restart the client when the script says the TOC changed (the game reads a TOC only at start). Read errors after the reload with `scripts/errors.sh`. Never type into the game client.
- Release: `scripts/release.sh patch|minor|major` tags `vX.Y.Z`; the release workflow packages it with the BigWigs packager once CI passes on that commit.
- Never commit SavedVariables, WTF data, logs or packaged zips.
