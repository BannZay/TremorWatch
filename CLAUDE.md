# TremorWatch

WoW 3.3.5a (Interface 30300) addon. Detects an enemy Tremor Totem (hostile `SPELL_SUMMON` of spell 8143 in the combat
log), shows its icon with a 3 s cooldown swirl and countdown for the next pulse, and optionally plays a sound on each pulse.
Author: BannZay.

## Files

- `TremorWatch.toc` – load order (version 2.0, MIT, see `LICENSE`), `SavedVariables: TremorWatchSettings, TremorWatchProfiles`. Libs are bundled and required (no lib-strip markers, no packager config).
- Runtime code is split into files that share a private table `ns` (`local _, ns = ...`); each file copies what it needs
  into locals at its top and exports with `ns.X = X` at its end. Load order (see the toc), each only uses earlier ones:
  - `Core.lua` – constants, `Keys`, the two sides (`ENEMY`/`ALLY`, also `frame.Sides.enemy/.ally`: frame, `slots` (one icon
    per shown totem, up to 3, oldest first; slot 1 is the frame itself and the drag handle; also `frame.Slots`), settings
    keys, location key), `defaults`, `MakeSlot`, the two frames (`TremorWatchMainFrame` enemies and event frame,
    `TremorWatchAllyFrame`) and `frame.Internal` (test hooks: `Now`, `IsArena`, `PlaySound`, `OnCombatLog`, `Tick`, `Update`, ...).
  - `Sounds.lua` – LibSharedMedia registration, sound name display/lookup, `PlayMedia`, `internal.Play*Sound`.
  - `Highlight.lua` – `REMOVABLE` and the `cc` table of fear/charm/sleep auras on enemies, `UpdateHighlight`.
  - `Totems.lua` – `totems[guid] = {summoned, seq, owner, friendly, test, seen, anchor, synced, swirl, nextSwirl,
    nextSound}` (the pulse schedule lives per totem), `Update()` (`UpdateSide` per side), `Resync`, the `timer` frame whose
    OnUpdate is `Tick`, add/destroy/expire, `OnCombatLog`, `UpdateRegistration`.
  - `Settings.lua` – `ApplyTestMode/Lock/Location/Look`, `OnSettingsUpdated`, drag/save position, `CopyDefaults`.
  - `Profiles.lua` – `NormalizeSettings`, profile API, `ns.InitProfiles`.
  - `Main.lua` – `Init` (on PLAYER_LOGIN), event handler, `/tw` slash commands.
- `BlizzardOptions.lua` – AceConfig options table registered in the Interface Options panel (`Keys` come from
  `TremorWatchMainFrame.Keys`; all options read/write `TremorWatchSettings.DB[key]`).
- `Sounds/mallet-alert.mp3` – default pulse sound; the other `Sounds/*.wav` are synthesized by `tools/gen_sounds.py` and
  registered in LibSharedMedia at load. `libs/` – bundled Ace3 / LibSharedMedia (third-party, do not edit).

## Saved data

Saved variables: `TremorWatchProfiles = { Profiles = { [name] = settings }, Chars = { ["Name-Realm"] = name } }`
(created in `Init` on PLAYER_LOGIN; settings saved before profiles existed become "Default" via the old
`TremorWatchSettings` saved variable, which is only a pointer to the active profile's table at runtime and is set to nil
on PLAYER_LOGOUT). Profile API on the main frame: `GetProfileNames/GetProfile/SetProfile/CreateProfile/CopyProfile/
DeleteProfile/ResetProfile`; the options live in the "Profiles" sub-panel. A profile's settings are
`{ Location, LocationAlly = {Point, RelativeTo (frame name string), RelativePoint, XOfs, YOfs},
DB = {...} }`. Shared DB keys: `arenaOnly`, `locked`, `latency`, `staleTimeout`.
Per-kind keys exist twice and are reached through the side's fields (`Track`, `Size`, `Alpha`, `MaxIcons`,
`IconSpacing`, `ShowPulses`, `Countdown`, `Sound`, `SpawnSound`, `DestroyFlash`, `DestroySoundName`, `AllowSounds`;
`Tint`; enemy also `Highlight`). Enemy keys are the original ones (`trackEnemies`, `size`, `showPulses`, ...),
ally keys are `trackAllies` and `ally`-prefixed (`allySize`, `allyShowPulses`, ...). Key names live in `Keys`. Defaults
are merged into the saved table in `Init` (saved variables replace anything assigned at file load), so new keys only
need an entry in `defaults`. Options: main panel plus "Enemy totems" / "Allied totems" sub-panels built by `SideOptions`.

## Behaviour notes

- Sound settings are LibSharedMedia names shown and saved as "name - addon" (`DisplaySoundName`: another addon's
  "Addon name" becomes "name - Addon", the addon being recognized from the installed addons' folder names; `PlayMedia`
  resolves either form; older raw names are converted in `NormalizeSettings`). The options use the `TremorWatchSound` widget
  (BlizzardOptions.lua: LSM30_Sound with a speaker per list row, widened list, plays by name via `PreviewSound`).
  Sound settings are LibSharedMedia names; `NO_SOUND` ("(None)", sorts first in the dropdown) means silent (there are no
  separate on/off toggles; old `playSounds`/`destroySound` toggles are migrated in `NormalizeSettings`). A spawn sound
  replaces the summon pulse sound of that totem. Fake (test) totems play sounds only with the `testSounds` debugging option.

- Sound mode per side (`soundMode` / `allySoundMode`: "swell" is the default, or "simple" = the pulse sound on the pulse; the old `swell` checkbox is migrated in `NormalizeSettings`). Swell: `SWELL_STEPS` (15) short rising sounds, one every `SWELL_STEP` (0.2 s) = the whole 3 s pulse interval, the last ending on the pulse; the side's `swellLength`/`allySwellLength` (seconds, 0.2..3, default 1.2) says how many of the last steps are played (`SwellTiming(side)` returns steps, step length, skipped steps); no pulse sound then. Presets (`SWELL_PRESETS`, key `swellPreset`/`allySwellPreset`): files `Sounds/swell/<preset>/<step>.wav`, and `Sounds/swell/<preset>/alert-<step>.wav` (a harsher, more dramatic sound per preset, not just louder; presets: notes, heartbeat, drops, ticks, bells, roll, sonar, arcade; the old "sweep" is migrated to drops) while the enemy frame glows (a fear/charm/sleep the pulse would remove); all made by `gen_sounds.py` (volume can not be set per `PlaySoundFile` in 3.3.5a, so levels are baked into files). Each step is a separate `PlaySoundFile` started from `Tick` (`totem.swellStep`), because a played sound can not be stopped: a destroyed totem leaves `totems` and its remaining steps are never started. Steps found more than one step late are skipped.

- Unlocking (`locked` false, also `/tw test`) enables the mouse (draggable) and shows as many fake totems as `maxIcons` on both frames
  (`ApplyTestMode`, keyed `testGUID .. i`). `locked` is
  saved, so a frame left unlocked shows the fake totem on the next load.
- `OnSettingsUpdated(key)` re-applies all settings on any option change; timing keys restart the pulse schedule.
- A tremor totem pulses on summon and every 3.00 s after (checked on the server: its pulse removes fear exactly then).
  The pulse logs no event of its own (no SPELL_DISPEL, only SPELL_AURA_REMOVED of the removed aura), so the schedule
  runs from the summon time. Sounds play only when a pulse boundary is crossed less than 0.5 s late; re-syncs are silent.
- Highlight: `cc[guid][spellId]` tracks auras from `REMOVABLE` (player spells with the fear, charm or sleep mechanic,
  all ranks, taken from Spell.dbc; tremor's effect 8146 dispels mechanics 1, 5, 10) on hostile units, from
  SPELL_AURA_APPLIED/REFRESH until REMOVED/BROKEN, unit death, zone change or 60 s. Whether the unit is in the totem's
  range is unknown.
- The client logs a totem's death (UNIT_DIED / UNIT_DESTROYED) only while the totem is in view; owner death and the
  stale timeout cover the rest. With "arena only" the combat log is only registered inside arenas.
- Only the Ace libs the options panel needs are bundled (AceConfig, AceGUI, CallbackHandler, LibStub,
  LibSharedMedia + its AceGUI widgets); the addon itself is a plain frame, not AceAddon.

## Testing

In-game tests: `Unit_Tests_TremorWatch` in the Trinity client's AddOns folder (not in this repo); run with the
`wow-ui-tests` skill, `-Filter TremorWatch`. Most tests drive `frame.Internal` with a fake clock and fake combat-log
events; one test has a real hostile NPC (entry 87) summon a totem on the server.
Check WoW API behaviour against `D:\Repositories\wowdecomp` rather than memory. Ask before any UI test.

## Release

`tools/release.ps1` builds `dist/TremorWatch-<version>.zip`. Checklist, packaging and the README screenshots (`screenshots/`,
taken by `Unit_Tests_TremorWatchShots` in the Trinity client): `wow-addon-release` skill.

## Conventions

Tabs for indentation, PascalCase for functions/keys, Lua 5.1 only (no `goto`, no `//`). Keep new variables `local`.
