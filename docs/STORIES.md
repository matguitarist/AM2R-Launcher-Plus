# AM2R Launcher Plus — Stories

Source: `docs/BRIEF.md`, `docs/ROADMAP.md`. No reference screenshots; `Screens:` names the snapshot
pages that show each story. Thimble tasks are named in `Thimble:` and their notes start with
`Story: S-xxx`.

Snapshot pages: `welcome`, `welcome-checking`, `welcome-error`, `install-progress`, `play`,
`play-running`, `play-failed`, `log-sheet`, `profiles`, `settings-game`, `settings-controls`,
`settings-general`, `update-banner`.

## M1 Install and play (0.1.0)

### S-001 Pick my AM2R 1.1 copy
As the player, on first launch I drop `AM2R_11.zip` (or the extracted folder) onto the welcome
window, or click Choose…, and the app checks that it is the real 1.1.
Screens: welcome, welcome-checking, welcome-error
Thimble: 0368a4d9
Acceptance:
- [unit] A zip or folder whose `data.win` MD5 is the 1.1 hash is accepted; anything else is rejected
  with the reason (wrong version, missing `data.win`, not a zip).
- [unit] The zip is hashed once; the result is cached by path + size + modified date.
- [snap] Checking shows a progress state; a wrong file shows the reason inline with a Choose Another… button.
- [self] The chosen location is kept as a security-scoped bookmark and survives a restart.
UX:
- Flow: first launch, or Profiles › Install Profile… -> welcome window with drop zone -> drop zip/folder or Choose… (⌘O, open panel filtered to .zip and folders) -> "Checking AM2R 1.1…" spinner -> accepted: "AM2R 1.1 found" checkmark and Install Community Updates button is focused. Way back: Choose Another…; Escape closes the open panel.
- Surface: the welcome page fills the main window (a place people come back to until a profile exists); no sheet.
- States: empty "Install AM2R on this Mac. Drop your AM2R_11.zip here, or choose it." with Choose…; loading "Checking AM2R 1.1…" (hashing ~1 s); error inline under the drop zone: "This isn't AM2R 1.1. Its data.win doesn't match the 1.1 release." / "No data.win in this folder." with Choose Another…; done: checkmark + file name (middle-truncated, full path in tooltip).
- Words: "Choose…", "Choose Another…", "Install Community Updates", note under the zone: "Your copy stays where it is. Nothing is uploaded."
- Access: drop zone is a button ("Choose AM2R 1.1"), Return activates it; status changes are announced; error has an icon and words, not only red.
Status: done

### S-002 Download the Community Updates patch data
As the player, after my 1.1 is accepted the app downloads the latest Mac patch data.
Screens: install-progress
Depends: S-001
Thimble: 78de5d4d
Acceptance:
- [unit] The latest commit of `Miepee/AM2R-Autopatcher-Mac` is read from the GitHub API; its archive is
  downloaded and unpacked to `PatchData/<sha>/`; `profile.xml` gives the version (1.5.5).
- [unit] An existing download for the same SHA is reused, not fetched again.
- [snap] Progress shows step name and percent; offline shows "Can't reach GitHub" with Try Again.
UX:
- Flow: Install Community Updates -> install progress page: step list "Downloading patch data", "Patching AM2R 1.1", "Copying game files" -> each step shows a checkmark when done -> S-004 end. Way back: Cancel (stops and removes partial files), returns to the welcome page.
- Surface: the install progress page replaces the welcome page in the window (long task the player watches; not a sheet, it can take a minute).
- States: loading: determinate bar for the download ("Downloading patch data — 18 of 31 MB"); error inline under the failed step: "Unable to reach GitHub. Check your connection, then try again." with Try Again; cached data skips the step with "Using downloaded patch data (1.5.5)".
- Words: "Cancel", "Try Again".
- Access: progress bar has label and value; step changes announced; Escape = Cancel.
Status: done

### S-003 Patch 1.1 into 1.5.5
As the player, the app turns my 1.1 into the 1.5.5 game files without any other tool installed.
Screens: install-progress
Depends: S-002
Thimble: 42f5c97c
Acceptance:
- [unit] The built-in VCDIFF decoder (Swift, LZMA via Apple Compression) applies `data/game.xdelta` to 1.1 `data.win`; the output MD5
  is `0de029951c94b04545c9c257053ad712` for 1.5.5.
- [unit] A failed or wrong-hash patch leaves no half-built profile behind.
UX:
- Flow: runs as the "Patching AM2R 1.1" step of the install progress page.
- Surface: same install progress page as S-002.
- States: loading indeterminate (a few seconds); error: "Patching failed. The patch data doesn't match this copy of AM2R 1.1." with Try Again and Show Log.
- Words: "Patching AM2R 1.1".
- Access: as S-002.
Status: done

### S-004 Build a playable profile
As the player, the patched files become a profile folder I can play.
Screens: install-progress, play
Depends: S-003
Thimble: 2b818266
Acceptance:
- [unit] `Profiles/<name>/` holds `game.ios`, every `.ogg` from 1.1 and `files_to_copy` (lowercased),
  `lang/` without `fonts/`, `mods/`, `*.txt`, `modifiers.ini`, `icon.png`, `splash.png`,
  `yoyorunner.config`, `English.lproj`, and the source `profile.xml`.
- [unit] The profile record stores version, patch SHA, engine = butterscotch, install date.
- [snap] When done, the window switches to the Play page for the new profile.
UX:
- Flow: "Copying game files" step -> "Community Updates 1.5.5 is ready" -> window switches to Play with the new profile selected and Play focused.
- Surface: install progress page, then the Play sidebar page.
- States: done: success line for one second, then Play page; error: "Unable to copy game files. There may not be enough space in the data folder." with Show Data Folder.
- Words: profile default name "Community Updates 1.5.5".
- Access: focus moves to Play; VoiceOver announces "Community Updates 1.5.5 is ready".
Status: done

### S-005 Play natively
As the player, I click Play and AM2R starts natively on Apple Silicon.
Screens: play, play-running
Depends: S-004
Thimble: 4f4d90de
Acceptance:
- [self] Play spawns the bundled `butterscotch` with the profile's `game.ios` and `--save-folder`
  pointing at the profile's save folder; the button turns into "Playing…" with a Stop button.
- [self] stdout/stderr go to `Logs/<profile>/<date>.log`; the last 5 logs are kept.
- [unit] Play time is added to the profile when the game exits.
- [manual] The game reaches the title and plays with keyboard and gamepad.
UX:
- Flow: Play button, ⌘P, Game › Play, Return on the Play page -> button becomes "Playing…" (disabled) with Stop beside it -> game window opens in front -> game quits -> button returns to Play, play time updates. Way back: Stop (⌘.) always asks "Stop AM2R? Unsaved progress will be lost." Stop / Cancel.
- Surface: Play sidebar page: header art, profile name + version + engine badge ("Native"), big Play button, last played and play time below.
- States: empty (no profile): Play page shows the welcome page instead; running: "Playing…" + Stop; done: "Last played just now · 2 h 14 min total".
- Words: "Play", "Playing…", "Stop", tooltip on engine badge "Runs natively on Apple silicon".
- Access: Play is the default button; Stop has ⌘.; badge has text, not just color.
Status: done

### S-006 See why the game stopped
As the player, if the game quits with an error I can read the log.
Screens: play-failed, log-sheet
Depends: S-005
Thimble: e5867719
Acceptance:
- [snap] A non-zero exit shows "AM2R stopped unexpectedly" with Show Log and Play Again.
- [snap] The log sheet shows the log in monospace with Copy and Reveal in Finder.
UX:
- Flow: game exits non-zero -> Play page shows an inline banner "AM2R stopped unexpectedly." with Show Log and Play Again -> Show Log opens the log sheet -> Done/Escape closes it.
- Surface: inline banner (information plus a fix, not an alert); log is a sheet (one short task: read, copy, close).
- States: log sheet empty: "The game didn't write anything."; too much: last 5,000 lines with "Reveal in Finder" for the full file.
- Words: sheet title "Log — Community Updates 1.5.5", buttons "Copy", "Reveal in Finder", "Done".
- Access: Escape closes the sheet; text view is selectable and VoiceOver-readable; banner has a warning icon plus words.
Status: done

### S-007 Bundle the engine
As the player, I never install Butterscotch myself: it ships inside the app.
Screens: settings-general
Thimble: 61e37b37
Acceptance:
- [unit] `tools/build-butterscotch.sh` clones Butterscotch at the commit in `Engine/BUTTERSCOTCH_COMMIT`,
  applies `patches/butterscotch/all-current.patch`, builds arm64 Release; `build.sh` bundles it as the
  helper app `Contents/Helpers/AM2R.app` (games category, Game Mode) with its license and patch.
- [snap] Settings › General shows the engine version and a "Source code (AGPL-3.0)" link.
UX:
- Flow: Settings (⌘,) › General -> "Engine" section: "Native (Butterscotch <commit>)", "Source Code (AGPL-3.0)" link opens the bundled source/patches page.
- Surface: Settings window, General tab (rarely visited reference info).
- States: engine missing from the bundle (dev builds): "Native engine not found. Use Rosetta, or reinstall the app." inline.
- Words: "Engine", "Native", "Source Code (AGPL-3.0)".
- Access: link is a real button with label; all text selectable.
Status: done

## M2 Tune the game (0.1.0)

### S-010 Choose display mode
As the player, I set windowed scale, fullscreen and widescreen before playing.
Screens: play
Depends: S-004
Thimble: 5c88f83a
Acceptance:
- [unit] Values are written to the profile save folder's `config.ini` under `[Screen]`
  (`Fullscreen`, `Scale`, `Widescreen`) without touching other keys.
- [unit] Values the game changed itself are read back when Settings opens.
Status: done

### S-011 Use the Mac-friendly controller layout
As the player, Select opens the map and Start opens the pause menu, out of the box.
Screens: play
Depends: S-004
Thimble: e39bca3f
Acceptance:
- [unit] Preset "Mac (Select = map, Start = pause)" writes `XBJoypadButtonStart=32777`,
  `XBJoypadButtonExit=32778`; preset "Original" writes 32778 / 32780.
- [unit] New profiles get the Mac preset.
- [snap] Controls shows the connected controller's name (GameController framework) or "No controller".
Status: done

### S-012 Pick the game language
As the player, I choose the game language from the ones the profile ships.
Screens: play
Depends: S-004
Thimble: 43c2d810
Acceptance:
- [unit] Languages are read from `lang/languages.txt`; the choice writes `[Screen] Language`.
Status: done

### S-013 Move the data folder
As the player, I can move where profiles and patch data live (e.g. an external drive).
Screens: settings-general
Thimble: f7d9603c
Acceptance:
- [unit] Moving copies, verifies, then deletes the old folder; a failure keeps the old one.
- [snap] Settings › General shows the path, size, Move… and Reveal in Finder.
Status: todo

### S-014 Use the Rosetta fallback for one profile
As the player, if a profile misbehaves on Butterscotch I can switch it to the official runner.
Screens: profiles
Depends: S-005
Thimble: 638031a3
Acceptance:
- [unit] Engine = rosetta builds `AM2R.app` (runner from `AM2R.xdelta`, `Frameworks`, `Info.plist`)
  and launches it with `open -W`.
- [snap] The engine picker says when Rosetta isn't installed and offers to install it.
Status: todo

## M3 Stay current (0.2.0)

### S-020 See that an update is available
As the player, the Play page tells me when a newer Community Updates release exists.
Screens: update-banner
Depends: S-002
Thimble: 18de8824
Acceptance:
- [unit] On launch (at most daily) the latest SHA and `profile.xml` version are compared with the profile.
- [snap] A banner shows "1.5.6 is available" with Update.
Status: todo

### S-021 Update a profile in one click
As the player, Update re-patches my profile and keeps my saves and settings.
Screens: install-progress
Depends: S-020, S-004
Thimble: 251ca765
Acceptance:
- [unit] The new profile is built beside the old one and swapped in only when complete; save folder
  and `config.ini` are untouched.
Status: todo

### S-022 Manage profiles
As the player, I see my profiles, rename, duplicate, reveal and delete them.
Screens: profiles
Depends: S-004
Thimble: f699c368
Acceptance:
- [snap] Profiles lists name, version, engine, last played, play time.
- [self] Delete asks for confirmation and offers to keep the saves.
Status: todo

### S-023 Back up and restore saves
As the player, I back up a profile's saves and restore one later.
Screens: profiles
Depends: S-022
Thimble: 376bee82
Acceptance:
- [unit] Backup zips the save folder with a date; restore asks before replacing.
Status: todo

## M4 Polish (0.3.0)

### S-030 Native look and icon
Screens: all
Thimble: 78530bc8, 5b37e6f7
Acceptance:
- [snap] Every page passes the mac-design and layout-grid checks in light and dark.
- [manual] The app icon reads at 16 px in the Dock and Finder.
Status: todo

### S-031 Game Mode
Thimble: 78863e48
Acceptance:
- [manual] Fullscreen AM2R turns on macOS Game Mode (engine helper declares the games category).
Status: todo

### S-032 Signed, notarized, self-updating app
Thimble: d8b988eb
Acceptance:
- [manual] A notarized DMG opens without warnings; Sparkle finds a test update.
Status: todo

## Later
- Mods: import a mod zip, install it as its own profile (3cab5910)
- Metal renderer and MetalFX upscaling in Butterscotch (a4f648ca)
- Randovania seeds (f110a069), mod browser (b9e9edd1), speedrun timer (ebb0cbde), Discord (bc5c6cc0)
- CLI / MCP (3d23b0ab), Rust data.win tools (c28e1acf), gmloader route (3bcc89ab)
- Localization of the launcher

## Dropped
- Accounts, cloud sync of profiles: one player on one Mac (iCloud save backup stays an idea).
- Android APK building (the original launcher does it): no Android target here.
- In-app news feed / changelog browser: the update banner links to the release notes instead.
