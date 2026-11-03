# AM2RLauncherPlus

A native Apple Silicon Mac app that turns your own AM2R 1.1 copy into the latest Community Updates
(1.5.5) and plays it natively, without Rosetta. Built for one player who wants AM2R to just work on a
modern Mac.

App name in the UI: **AM2R Launcher Plus**. Bundle id: `com.mathieu.am2rlauncherplus`. Folder: this
project (`~/Developer/Am2r-launcher-plus`). _Decided by the agent._

## Replaces
The community AM2RLauncher (whose Mac build is "unsupported", .NET, x86_64), plus the manual routine
of patching 1.1 and running the official GameMaker runner under Rosetta.

## Main jobs
1. **Set up once:** pick `AM2R_11.zip` (or the extracted folder), check it is a real 1.1, download the
   Community Updates patch data, patch, and build a playable profile.
2. **Play:** one big Play button that launches the profile on the bundled Butterscotch engine (native
   arm64), with Rosetta + official runner as a fallback per profile. Show the game log if it fails.
3. **Tune the game:** display (windowed scale, fullscreen, widescreen), controller preset
   (default: Select = map, Start = pause menu), language, written to the game's own `config.ini`.
4. **Stay current:** see when a newer Community Updates release exists and update in one click.

## Data
- **GameSource:** zip or folder path (security-scoped bookmark), MD5, validated date.
- **Profile:** name, version (e.g. 1.5.5), install folder, engine (butterscotch / rosetta),
  save folder, patch-data commit, installed date, last played, play time.
- **PatchRelease:** version, commit SHA, download URL, downloaded date (cache of what's available).
- Settings (not a model): data folder location, default engine, controller preset.

## Shape
One window with a sidebar (Play, Profiles, Settings; Mods arrives in 0.2.0), macOS 26 or later,
Liquid Glass. Local data in `~/Library/Application Support/AM2RLauncherPlus`, movable.
Needs the internet only to download patch data and check for updates. No accounts.

## System hooks
None in version one. Later: CLI/MCP (`bama:agent-cli`), Game Mode keys in the game bundle.

## Reference
AM2RLauncher (behavior only: validate zip, PatchData, xdelta patch, profile, launch). Its UI is not a
reference.

## Look
Native Mac app with its own accent: Metroid green-teal (title-screen planet glow, ~#3FD1B0), dark
first. Play page has a large game art header. _Decided by the agent._

## Not in version one
- Mods and mod profiles (0.2.0), save backup/restore (0.2.0)
- Randomizer, mod browser, speedrun timer, Discord, MetalFX (Ideas)
- Self-update, signing and notarization (0.3.0)

## Constraints
- Never ship or redistribute AM2R game files; the user's 1.1 is the only source.
- Butterscotch is AGPL-3.0: bundled as a separate executable, our patches kept in
  `patches/butterscotch/` and offered upstream.
- Project license still open (Thimble task 7571e786, owner's call).
