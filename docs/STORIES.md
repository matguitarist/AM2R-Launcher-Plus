# AM2R Launcher Plus — Stories

Source: `docs/BRIEF.md`, `docs/ROADMAP.md`. No reference screenshots; `Screens:` names the snapshot
pages that show each story. Thimble tasks are named in `Thimble:` and their notes start with
`Story: S-xxx`.

Snapshot pages: `welcome`, `welcome-checking`, `welcome-error`, `install-progress`, `play`,
`play-running`, `play-no-rosetta`, `play-failed`, `log-sheet`, `profiles`, `profiles-delete`, `saves-backups`, `debug-log-launcher`, `debug-log-game`, `settings-game`, `settings-controls`,
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
Status: done

### S-014 Use the Rosetta fallback for one profile
As the player, if a profile misbehaves on Butterscotch I can switch it to the official runner.
Screens: play-no-rosetta
Depends: S-005
Thimble: 638031a3
Acceptance:
- [unit] Engine = rosetta builds `AM2R.app` (runner from `AM2R.xdelta`, `Frameworks`, `Info.plist`)
  and launches it with `open -W`.
- [snap] The engine picker says when Rosetta isn't installed and offers to install it.
UX:
- Flow: Play page › Engine section (or Game › Engine, ⌥⌘1 Native, ⌥⌘2 Rosetta) -> Rosetta builds `<profile>/AM2R.app` once ("Building the Rosetta app…"), then Play runs it. Saves and config.ini are shared with Native: the runner's Application Support/<bundle id> links to the profile's save folder.
- States: Rosetta missing: "Rosetta isn't installed on this Mac." with Install Rosetta… (asks first, then softwareupdate with an administrator password); no AM2R.exe: the reason under the picker; build failure: the reason, engine stays Native.
Status: done

## M3 Stay current (0.2.0)

### S-020 See that an update is available
As the player, the Play page tells me when a newer Community Updates release exists.
Screens: update-banner
Depends: S-002
Thimble: 18de8824
Acceptance:
- [unit] On launch (at most daily) the latest SHA and `profile.xml` version are compared with the profile.
- [snap] A banner shows "1.5.6 is available" with Update.
Status: done

### S-021 Update a profile in one click
As the player, Update re-patches my profile and keeps my saves and settings.
Screens: install-progress
Depends: S-020, S-004
Thimble: 251ca765
Acceptance:
- [unit] The new profile is built beside the old one and swapped in only when complete; save folder
  and `config.ini` are untouched.
Status: done

### S-022 Manage profiles
As the player, I see my profiles, rename, duplicate, reveal and delete them.
Screens: profiles
Depends: S-004
Thimble: f699c368
Acceptance:
- [snap] Profiles lists name, version, engine, last played, play time.
- [self] Delete asks for confirmation and offers to keep the saves.
Status: done

### S-023 Back up and restore saves
As the player, I back up a profile's saves and restore one later.
Screens: saves-backups
Depends: S-022
Thimble: 376bee82
Acceptance:
- [unit] Backup zips the save folder with a date; restore asks before replacing.
Status: done

## M4 Polish (0.3.0)

### S-030 Native look and icon
Screens: all
Thimble: 78530bc8, 5b37e6f7
Acceptance:
- [snap] Every page passes the mac-design and layout-grid checks in light and dark.
- [manual] The app icon reads at 16 px in the Dock and Finder.
Notes: Icon is a play triangle over a planet with a small moon, on a teal gradient (checked at 16 pt with tools/icon_review.sh). Play page scrolls as one form; Welcome and Install pages carry grid probes; radii come from `Radius`.
Status: done

### S-031 Game Mode
Thimble: 78863e48
Acceptance:
- [manual] Fullscreen AM2R turns on macOS Game Mode (engine helper declares the games category).
Notes: Engine/Info.plist sets LSApplicationCategoryType games and LSSupportsGameMode; the engine uses native full screen. Seen 2026-11-03 in gamepolicyd's log: "Found game butterscotch (labelReason=LSSupportsGameMode)", "Game mode status is now on", off when the game quit. Check: `/usr/bin/log show --last 1h --predicate 'process == "gamepolicyd"' | grep -i "game mode"` (plain `log` is a zsh builtin).
Status: done

### S-032 Signed, notarized, self-updating app
Thimble: d8b988eb
Notes: Sparkle 2 is wired in (feed: appcast.xml of the latest GitHub release, EdDSA key in the login Keychain, account "am2rlauncherplus"); tools/release.sh builds, notarizes and publishes. Done after the first real release is found by an older build.
Acceptance:
- [manual] A notarized DMG opens without warnings; Sparkle finds a test update.
Verified 2026-11-03: the published 0.2.1 app (notarized, Gatekeeper accepted) found 0.2.2 with Check for Updates… and installed it. A copy must not be running from ~/Applications while release.sh rebuilds it (the script now quits it), or Sparkle's installer rejects the changed signature.
Status: done

## M5 Mods (0.3.0)

### S-033 Install a mod as its own profile
As the player, I add an AM2R mod zip and play it as its own profile next to Community Updates.
Screens: profiles, install-mod, install-mod-error, play-mod
Depends: S-004, S-022
Thimble: 3cab5910
Notes: AM2RLauncher mod zips hold profile.xml (Name, Version, Author, OperatingSystem, UsesYYC, UsesCustomMusic, ProfileNotes), data.xdelta (Windows) or game.xdelta (Linux, Mac) against AM2R 1.1's data.win, AM2R.xdelta (a runner) and files_to_copy/. The native engine runs the patched game data of every system, so Windows and Linux mods play too. YYC mods have their code compiled into the runner and can't. Mods play on the native engine only; they get no Community Updates update banner.
UX:
- Flow: Profile › Install Mod… (⌥⌘O), or drop a .zip on the Profiles page -> open panel filtered to .zip -> the install page "Installing <Mod> <version>" with Reading the mod, Patching AM2R 1.1, Copying game files -> the new profile's Play page. Way back: Cancel during install; Escape closes the open panel.
- Surface: the same install page as Community Updates, in the main window; no sheet.
- States: no AM2R 1.1 yet -> the menu item is off, with help "Install AM2R first"; reading/patching/copying as for Community Updates; error inline on the install page with Choose Another Mod… and Cancel; done -> "<Mod> is ready", then Play.
- Words: "Install Mod…", "Choose Another Mod…", errors: "This zip isn't an AM2R mod. It has no profile.xml." / "<Mod> is built with YYC, so it only runs with its own Windows runner." / "<Mod> has no patch for the game data." / "Patching failed. This mod doesn't match AM2R 1.1." Play page: "Version 1.2 · by <Author> · Native".
- Access: the progress steps are announced as for Community Updates; errors have an icon and words.
Acceptance:
- [unit] A mod zip is read: profile.xml at the top or one folder down, game.xdelta preferred over data.xdelta, YYC and patch-less mods refused with a reason, macOS junk (__MACOSX) ignored.
- [unit] profile.xml attributes are read by name: Version="1.2" wins over XMLVersion="1", &amp; is decoded.
- [self] Installing a mod builds a profile with the mod's name, version and author, marked as a mod, on the native engine, with no update banner.
- [snap] The install page shows the mod's name; the Play page shows the author.
- [manual] A real community mod installs and plays.
- [snap] The Mods page lists installed mods with Play, and the community mod list (gitlab.com/Miepee/AM2R-Mods) by group with Get; offline it says so with Try Again.
Status: todo

## M6 Our patch (0.4.0)

One game patch of our own, "AM2R Launcher Plus patch", built with UndertaleModLib (a .NET tool on the developer's Mac only) and shipped in the app as an xdelta against the Community Updates game.ios the launcher installs. Players need no tools. Its features read keys the launcher writes to config.ini, so one patch serves every combination of settings. It is rebuilt for each Community Updates release; a profile on another version plays unpatched.

### S-034 Button prompts that match my controller
As the player with a PlayStation, Switch or other controller, I see that controller's buttons in the game's hints and menus, not Xbox letters.
Screens: play (Controller section)
Depends: S-011, S-033
Thimble: 97133751
Notes: AM2R draws prompts with get_button_sprite. The patch adds prompt sprite sets we draw ourselves (no console maker's art) and picks one by [Control] ButtonPrompts in config.ini. The launcher writes it from the connected controller (GCController productCategory), or from the player's choice.
UX:
- Flow: Play page > Controller > Button Prompts: Automatic (default), Xbox, PlayStation, Nintendo, Generic.
- States: patch not available for this profile's version -> the picker is off, with footer "Button prompts need Community Updates <version>."
- Words: "Button Prompts", "Automatic (matches your controller)".
Acceptance:
- [unit] A controller's product category maps to a prompt set; unknown ones get Generic.
- [unit] The patch applies to the shipped Community Updates game.ios and the result starts with FORM.
- [self] A patched profile with ButtonPrompts set starts and ends cleanly.
- [manual] With a PlayStation controller, in-game hints show the PlayStation shapes.
Status: todo

### S-035 Comfort tweaks
As the player, I turn on small changes that make AM2R easier to live with, each one on its own.
Screens: play (Tweaks section)
Depends: S-034
Thimble: 8c36e1da
Notes: Same patch, one config.ini key per tweak under [LauncherPlus]. First set: skip item get cutscenes' fanfare wait, faster save station, metroid counter per area on the map.
UX:
- Flow: Play page > Tweaks: one toggle per tweak, each with a one-line description; all off by default.
- States: patch not available -> the section says why, as in S-034.
Acceptance:
- [unit] Each tweak toggle writes its key and leaves the rest of config.ini as it was.
- [self] With every tweak on, the patched game starts and ends cleanly.
- [manual] Each tweak does what its description says in a real game.
Status: todo

### S-036 Play a Randovania seed
As a randomizer player, I make a seed in Randovania and play it in the launcher.
Screens: profiles, install-randovania
Depends: S-004, S-033
Thimble: f110a069
Notes: Randovania (with .NET) patches a folder holding AM2R.app/Contents/Resources/game.ios (Community Updates 1.5.5) and exports the same layout. The launcher makes that input folder from a Community Updates profile and imports the exported folder as a profile marked as a mod (native engine, no update banner, own saves).
UX:
- Flow: Profile > Prepare for Randovania… -> a folder in Finder to choose as Randovania's input; Profile > Import Randovania Game… (or drop the exported folder on Profiles) -> the install page -> the new profile's Play page.
- Words: "Prepare for Randovania…", "Import Randovania Game…", error "This folder has no Randovania game. Export the seed from Randovania first."
Acceptance:
- [unit] An exported folder is recognized by AM2R.app/Contents/Resources/game.ios; anything else is refused with a reason.
- [self] Preparing writes AM2R.app/Contents/Resources with the profile's game files; importing that folder back builds a profile.
- [manual] A real Randovania seed exports from the prepared folder, imports, and plays.
Status: todo

## Later
- Metal renderer and MetalFX upscaling in Butterscotch (a4f648ca)
- Mod browser (b9e9edd1), speedrun timer (ebb0cbde), Discord (bc5c6cc0)
- CLI / MCP (3d23b0ab), Rust data.win tools (c28e1acf), gmloader route (3bcc89ab)
- Localization of the launcher

## Dropped
- Accounts, cloud sync of profiles: one player on one Mac (iCloud save backup stays an idea).
- Android APK building (the original launcher does it): no Android target here.
- In-app news feed / changelog browser: the update banner links to the release notes instead.
