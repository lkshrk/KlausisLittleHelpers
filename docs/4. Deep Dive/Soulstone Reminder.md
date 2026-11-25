# Deep Dive: Soulstone Reminder

## Overview

Soulstone Reminder (feature key `SoulstoneReminder`, Forever only, QoL tab, section "Dungeons & Raids") warns in a dungeon or raid when a warlock's soulstone is ready and no Priest, Paladin, Shaman or Druid has the Soulstone Resurrection buff. It is switchable live: an Enable toggle, off by default, that takes effect without a reload (the spec has `disable`). `enable` creates the event frame, banner, tracker, throttle and peers once and reuses them, and registers the `KLH` prefix once. `disable` unregisters every event, hides the banner, ends test mode and clears held triggers, queued refreshes and HELLO state; a `running` flag makes timers that fire afterwards do nothing.

## Files

- **`Modules/SoulstoneLogic.lua`** (`ns.Soulstone`): pure. `Evaluate(snap)` returns the banner `rows` (`"No Soulstone on healer"`, then "Put your soulstone on <suggest>" when you are the ready warlock, then one "Ready: <name without realm>" per other ready warlock), the announce line and the whispers, or `nil`. `NewTracker()` keeps the 30 min cooldown of other warlocks by GUID. `NewThrottle()` allows chat once per trigger and at most once per 60 s.
- **`Modules/SoulstoneReminder.lua`**: reads the roster, auras, bags and item cooldown, listens to events, draws the banner and sends chat.
- Tests: `.tools/tests/soulstone_test.lua` (decision, tracker, throttle), `.tools/tests/soulstonewiring_test.lua` (events, banner, chat, options) and `.tools/tests/soulstonecomms_test.lua` (peer HELLO messages and lowest-GUID sender election). `.tools/tests/livefeature_test.lua` covers the live switch.

## Rules

- Active only in `party` or `raid` instances, as chosen by "Active in".
- Nothing is drawn or sent while the group is busy: the player in combat, any group unit `UnitAffectingCombat`, `IsEncounterInProgress()`, or the player `UnitIsDeadOrGhost`. A trigger (combat end, ready check) that arrives then is held and retried every second until the group is clear, then fires once.
- Members with `UnitIsConnected` false are skipped, so they are never suggested or whispered. Members whose raid-roster zone (`GetRaidRosterInfo`) differs from the player's are outside the instance: they count as having no soulstone and are neither suggested nor whispered. If a resurrecting member inside the instance (or of unknown zone) is not `UnitIsVisible`, their buff state is unknown and nothing is shown.
- `/klh soulstone` prints whether the reminder would show right now and, if not, why (`Evaluate` returns the reason as its second value), followed by each resurrecting member and warlock with level, range or zone, soulstone and readiness.
- Levels: a warlock counts from level 18. Resurrecting classes count from their resurrect level: Priest 10, Paladin 12, Shaman 12, Druid 20 (Rebirth). Below that they neither need nor cover a stone.
- Any counted resurrecting member with the buff covers the group; a stone on any other class does not.
- Your own stone is ready when a soulstone item is in your bags and its cooldown is 0 or only the global cooldown (1.5 s or less). Another warlock's is ready until a use is seen, then for 1800 s from that use it is not.
- Use signals, all feeding `tracker:OnUsed` (which keeps the latest time, so repeats and older times change nothing):
  - Main: a Soulstone Resurrection buff on any group member (any class). The aura's `sourceUnit`, resolved with `UnitGUID`, is the caster, and `expirationTime - duration` (on the `GetTime` clock) is the cast time. During combat `UNIT_AURA` runs only this scan, secret-safe, and draws nothing.
  - `UNIT_SPELLCAST_SUCCEEDED` from a group unit of class Warlock with a soulstone spell ID.
  - The combat log is not used: registering `COMBAT_LOG_EVENT_UNFILTERED` is a protected action on Forever (ADDON_ACTION_FORBIDDEN).
- Announces always go to `INSTANCE_CHAT` (`/i`), which works in any group inside an instance on Forever (checked in game).
- One sender per group: `ns.Soulstone.NewPeers()` (`:Seen`, `:Prune`, `:Elected`) keeps the KLH clients seen in the group. Clients with Announce or Whisper on register prefix `KLH` and send `SSR1:HELLO` (to `INSTANCE_CHAT` in instance groups, otherwise `RAID` or `PARTY`), out of combat and inside an allowed instance: on a roster change, joining or entering the instance (at most once per 10 s), and before a trigger when the last one is over 60 s old. A trigger waits 2 s after a HELLO so peers can answer. Each receiver records the sender (name resolved to a GUID through the roster) and replies with its own HELLO, at most once per 10 s. Peers leave on leaving the group or after 5 min unseen. On a trigger only the lowest GUID among self and peers sends the announce and whispers; banner and sound stay per client. Without the API, or when a send fails, the client announces itself.
- The banner appears on any roster, aura, zone or bag cooldown change; chat and sound only on a trigger. Right-click hides it until the next trigger; left-drag moves it only while the test banner is shown (from the options).
- Banner look: no backdrop, border or close button. A centred vertical stack: the 40 px soulstone icon, then the rows as outlined, shadowed FontStrings (row 1 in warlock purple). The height follows the row count. While shown, an `OnUpdate` bobs the icon (the rows hang off it) 0 to 8 px on a cosine curve, one full cycle per second; hiding stops it and resets the icon. A looping Translation with `BOUNCE` flickered at the top turn in game.
- "Show test banner" (available only while the feature runs) turns into "Hide test banner" while shown, and a second click hides it. It keeps the sample banner up through refreshes with the icon, row 2 and two sample Ready rows until it is right-clicked, combat starts, or 30 s pass.

## Game data

From wago.tools, Forever build 1.60.1.71037: buff spells 20707, 20762, 20763, 20764, 20765 (Soulstone Resurrection); items 5232, 16892, 16893, 16895, 16896 (Minor to Major Soulstone); each item's effect has a 1800000 ms category cooldown (category 831).
