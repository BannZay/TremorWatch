# TremorWatch

World of Warcraft 3.3.5a addon. Shows an icon when an enemy Tremor Totem is nearby, with a swirl and a countdown to
its next pulse and an optional sound on each pulse.

Source code and issues: https://github.com/BannZay/TremorWatch

## Screenshots

![Enemy Tremor Totem with countdown](screenshots/single-totem.png)

![Icon glowing while a fear would be removed by the next pulse](screenshots/fear-glow.png)

![Tremor Totem nameplate with the square icon](screenshots/nameplates_squared.png)
![Tremor Totem nameplate with the round icon](screenshots/nameplates_round.png)

![Main options](screenshots/options-main.png)
![Enemy totem options](screenshots/options-enemy-totems.png)
![Allied totem options](screenshots/options-allied-totems.png)

## Options

`/tw` (or `/tremorwatch`) opens the options panel (Interface Options > AddOns > TremorWatch).

Enemy and allied totems each have their own frame (own position, size and settings). Unlock the frames to see a fake
totem on each and drag them; allied totems are off by default.

- **TremorWatch** (main panel, shared)
  - **Unlock frame / Lock frame** button (unlocked, as many fake totems as its **Max icons** are shown on each
    frame, so you can drag it and check spacing and size), **Reset positions**, **Show on arena only** (ignore totems outside arenas; the combat log is not read
    there at all), **Forget unseen totems** (outside arenas, drop a totem when neither it nor its shaman was seen for
    that long), **Latency compensation** (pulses follow the server's clock, half your latency earlier), and
    **Debug sounds** (the fake totems shown while the frames are unlocked also play their spawn and pulse sounds;
    silent by default).
- **Enemy totems** and **Allied totems** (sub-panels, same settings, own values)
  - **Track enemy / allied totems** (enemies default on, allies off).
  - **Frame** - **Max icons** (1-3; each shown totem gets its own icon, oldest on the left, more are counted as "+N"
    on the last icon), **Icon spacing**, **Icon size**, **Alpha**.
  - **Icon** - **Show** (default on; off hides that frame, the totems are still tracked for sounds and nameplates),
    **Show pulses** (swirl), **Countdown text**, **Flash** (grey icon for a second when a shown totem is destroyed),
    **Tint** (red for enemies, green for allies; on by default).
    Enemies also have **Highlight removals** (the icon glows while an enemy has a fear, charm or sleep effect -
    Psychic Scream, Fear, Seduction, Wyvern Sting, ... - that the next pulse will remove).
  - **Sound** - **Enable** (default on for enemies, off for allies; off silences every sound of that frame, whatever
    its own sound settings), **Spawn sound** (played when a totem appears; it replaces the pulse sound of the summon itself),
    **Destroyed sound** (when a shown totem is destroyed), and under **Pulses** the **Sound mode** with the
    **Pulse sound** or the swell.
  - Sounds are chosen from the LibSharedMedia list in a dropdown with a **Play** button; **(None)** at the top of each
    list means no sound. Names read "name - addon" ("Bell - CombatTracking" for another addon's "CombatTracking Bell"). Bundled: mallet (default enemy pulse sound), tick, blip (pulses), rise, ding-dong (spawn),
    shatter, fall (destroyed). Allied sounds default to None. The WAVs are made by `tools/gen_sounds.py`.
  - **Nameplate** (only while that side is tracked) - **Recolor Nameplate** (default on for enemies, off for allies)
    paints the totem's health bar in the **Health bar color** (cyan for enemies; works without the icon too).
    **Hide name** hides the name text on the totem's nameplate. **Add Icon** (default on for enemies, off for allies) puts a large
    glowing Tremor icon on the totem's nameplate. The icon does not take the mouse, so hovering or clicking it reaches
    the nameplate underneath (a `[target=mouseover]` macro works on it) and the nameplate's click area is unchanged.
    **Style**: square (like the TremorWatch frame, with the swirl) or round (with a colored ring, no swirl). Also
    **Icon size**, **Vertical offset**, **Pulsing glow** and **Glow color**. **Pulse ticks** adds a pulse counter
    and a flash on each pulse; **Counter**: swipe (the swirl and a countdown) or growing border (borders in the
    **Border color** appear one by one around the icon as the pulse comes closer). Needs the nameplates of that side
    shown; with **Show on arena only** it works in arenas only. When several Tremor Totems of one side are up, a plate
    only gets a countdown once it has been targeted or hovered.
- **Profiles** (sub-panel) - each character uses one profile (default "Default"); characters on the same profile share
  all settings and positions. **Current profile**, **New profile** (starts with default settings), **Copy from**,
  **Delete profile** (not the one in use), **Reset profile**. Settings saved before profiles existed become "Default".

Slash commands: `/tw lock` / `/tw unlock` (`/tw test` toggles), `/tw reset` resets the frame positions, `/tw profile <name>` switches profile, `/tw plates` prints what the nameplate highlight sees (for troubleshooting).

## License

MIT, see `LICENSE`. The bundled libraries in `libs/` (Ace3, LibStub, CallbackHandler, LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets) keep their own licenses.
