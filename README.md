# Klausi's Little Helpers

Small helpers for questing, routes and professions. Runs on retail and WoW Forever.

## Features

- Farm Tracker: tracks fishing and farming sessions, loot and shared area history (retail and Forever). Its watcher shows the current area and paused state above the session summary, with pause and stop controls in the header.
- Minimap Button: left-click for settings, right-click for helpers, or drag to move it (retail and Forever).
- TustUI Enhanced XP Bar: session XP and XP/hour on TustUI's XP bar (retail and Forever).
- RestedXP Quest Sync: keeps your quest tracker on the current RestedXP guide (Forever).
- Turn-in Route: plans the fastest route to every ready turn-in (Forever).
- Writ & Crate Planner: cheapest writs, crates and delivery receipts for a rep or Merchant's Favor target from Auctionator prices with a price check against the usual price from its history and a buy-or-wait indicator on its auction house button, plus macros to apply receipts and fill crates (Forever). User-reported in-game rewards, not verified DB2 data, are 5 Favor for Artisan Textiles (which yields a Sealed Apprentice crate), 20 for other Artisan gathered crates, and 40 for Artisan crafted crates.
  Trend estimates use log-linear daily prices only when at least 80% of the cost is observed or carried at most three days and at least 20% is observed that day. They require five qualifying days spanning seven days, a recent sample, and consistent leave-one-out direction. Missing attribution or insufficient history suppresses the estimate.
- Soulstone Reminder: warns in dungeons and raids when a warlock's soulstone is ready and no healer has one (Forever).
- Layer Change Prompt: moves Blizzard's "you will be moved to another layer" prompt where you want it and keeps it on top of other frames (Forever).

Open it with `/klh`.

Documentation is in [docs/](docs/). To build, test or release, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Saved settings

This version starts a new `KLH_Store` SavedVariable and does not import settings or character data from the old `KLH_DB` and `KLH_CharDB` variables. Existing settings therefore start fresh. Back up your SavedVariables before upgrading if you want to retain a copy of the old data. Profiles are managed by AceDB. Characters without a profile mapping share the `Default` profile; existing profile selections are preserved.

## License

GPL-3.0, see [LICENSE](LICENSE). The turn-in data in `Data/Writs.lua` is derived from [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0). The fetched Ace3 libraries in `Libs/` keep their own license, see [Libs/LICENSE-Ace3.txt](Libs/LICENSE-Ace3.txt); LibStub is public domain.
