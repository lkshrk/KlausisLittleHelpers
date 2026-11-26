# Klausi's Little Helpers

Small helpers for questing, routes and professions. Runs on retail and WoW Forever.

## Features

- TustUI Enhanced XP Bar: session XP and XP/hour on TustUI's XP bar (retail and Forever).
- RestedXP Quest Sync: keeps your quest tracker on the current RestedXP guide (Forever).
- Turn-in Route: plans the fastest route to every ready turn-in (Forever).
- Writ & Crate Planner: cheapest writs, crates and delivery receipts for a rep or Merchant's Favor target from Auctionator prices with a price check against the usual price from its history, plus macros to apply receipts and fill crates (Forever).
- Soulstone Reminder: warns in dungeons and raids when a warlock's soulstone is ready and no healer has one (Forever).
- Layer Change Prompt: moves Blizzard's "you will be moved to another layer" prompt where you want it and keeps it on top of other frames (Forever).

Open it with `/klh`.

Documentation is in [docs/](docs/). To build, test or release, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0, see [LICENSE](LICENSE). The turn-in data in `Data/Writs.lua` is derived from [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0). The vendored Ace3 libraries in `Libs/` keep their own license, see [Libs/LICENSE-Ace3.txt](Libs/LICENSE-Ace3.txt); LibStub is public domain.
