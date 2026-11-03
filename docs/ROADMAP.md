# AM2R Launcher Plus — Roadmap

_Started 2026-11-03. Tracked in Thimble as **AM2R Launcher Plus Roadmap**._

## What it is

A native Apple Silicon macOS launcher for AM2R (Another Metroid 2 Remake), written in Swift/SwiftUI.
It does what the community AM2RLauncher does (install and update the Community Updates from your own
`AM2R_11.zip`, manage mods, launch the game), with a Mac-first UI and room to grow: a mod library,
graphics options, save management, randomizer support.

The original launcher calls macOS "unsupported" and its Mac build is a .NET/Eto.Forms port with
missing pieces (no bundled xdelta, no arm64 binary). That gap is what this project fills.

## How the original launcher works (what we must reproduce)

Read from `AM2RLauncher/AM2RLauncherLib` (`Profile.cs`, `CrossPlatformOperations.cs`):

1. **Validate the user's `AM2R_11.zip`** — checks contents and MD5 (cached so it isn't rehashed).
   No copyrighted files are ever shipped.
2. **Fetch PatchData** — git clone/pull of the autopatcher repo. Mac uses
   `github.com/Miepee/AM2R-Autopatcher-Mac`. It holds `profile.xml`, xdelta patches, `Frameworks/`,
   `Info.plist`, `PkgInfo`, and optional `HDR_HQ_in-game_music`.
3. **Build the profile** into `Profiles/<name>/AM2R.app/Contents/{MacOS,Resources,Frameworks}`:
   - xdelta3-patch `data.win` → `Resources/game.ios` and `AM2R.exe` → `MacOS/` runner.
   - copy datafiles (lang, mods, `modifiers.ini`), optional HQ music.
   - Mac fixes: lowercase every `.ogg`, delete `lang/fonts` (custom fonts crash on Mac).
   - copy `Frameworks`, `Info.plist`, `PkgInfo`; copy `profile.xml` for later update checks.
4. **Mods** are zips with a `profile.xml` (`Name`, `Version`, `Author`, `OperatingSystem`,
   `SaveLocation`, `UsesCustomMusic`, `UsesYYC`, `SupportsAndroid`, `Installable`, `ProfileNotes`).
   They live in `Mods/<name>` and install like the main profile.
5. **Launch** with `open AM2R.app -W`, optionally `--stdout/--stderr` to a rolled-over log file.

**Platform fact that shapes everything:** the official GameMaker: Studio 1.4 macOS runner is
x86_64 + OpenGL and needs **Rosetta 2**. Apple keeps Rosetta fully only through macOS 27; from
macOS 28 only a reduced "games subset" remains, with an unclear scope. So Rosetta is a fallback, not the plan.

**Native path: run the game on Butterscotch.** AM2R's `data.win` is VM bytecode (checked
2026-11-03 on the 1.1 file: GEN8 bytecode version 14, has a `CODE` chunk, so it isn't YYC).
[Butterscotch](https://github.com/ButterscotchRunner/Butterscotch) is an open-source C
reimplementation of the GameMaker runner. It supports WAD 8–17 (GMS 1.0–2.2), builds for macOS
arm64 with an AppKit backend, is AGPL-3.0, and is very active. If it plays AM2R (1.1 and the 1.5.x
Community Updates data), the game itself runs natively on Apple Silicon. We also control the
renderer then, so a Metal renderer, MetalFX upscaling and shader filters become real options.
- Keep it a **separate executable** the launcher bundles and spawns. That keeps the AGPL boundary
  clean and lets us track upstream. Send fixes upstream as normal PRs.
- With Butterscotch, the launcher patches `data.win` only (no runner patch, no `Frameworks`).
- Fallback: the official runner under Rosetta, while Rosetta exists.
- Second fallback (research): the Android ARM runner via a gmloader-style loader (PortMaster's
  approach on ARM Linux, known to run AM2R 1.5.x), with GLES on ANGLE→Metal.

## Architecture

- **Swift 6 + SwiftUI**, macOS 26+, Liquid Glass, built with the bama template (Swift package, no Xcode GUI).
- Modules: `AM2RCore` (zip validation, PatchData sync, patching, profile building, launching),
  `ModLibrary`, and the app UI. Core has no UI so it can drive a CLI later.
- **Patching:** compile xdelta3's C sources into a SwiftPM target (universal arm64/x86_64).
  No runtime dependency, no Homebrew.
- **PatchData sync:** download the repo archive over HTTPS (GitHub API, GitLab mirror as fallback)
  instead of bundling libgit2. Check by commit SHA.
- **Rust: not on day one.** It earns a place later for one job: a fast, safe parser and differ for
  GameMaker `data.win`/`game.ios` files (mod inspection, building mods from a modified game,
  conflict checks). Expose it with UniFFI as a static lib. Until then, Swift + C covers it.
- **Licensing:** this project is GPL-3.0-or-later (decided 2026-11-03), like AM2RLauncher and the
  Mac patch data.
  AM2R-Community-Updates is "all rights reserved": consume its published patches only, never
  redistribute game files. AM2RLauncher's AGENTS.md asks that agent-driven work not be sent upstream;
  keep this project separate.

## Milestones

### 0.1.0 — Play AM2R natively-launched on Apple Silicon
- Brief and user stories (`docs/BRIEF.md`, `docs/STORIES.md`)
- **Spike first: run AM2R 1.1 and Community Updates 1.5.x on Butterscotch (arm64)** — decides the game engine
- Scaffold the SwiftUI app
- First-run onboarding: pick `AM2R_11.zip` (or the extracted folder), validate it
- Bundle and launch Butterscotch; Rosetta + official runner only as a fallback
- PatchData sync (download, version check, mirror fallback)
- xdelta3 patcher module
- Build the Community Updates profile into `AM2R.app` with the Mac fixes
- Launch, watch the process, capture logs
- Data folder in `~/Library/Application Support`, movable like `AM2RLAUNCHERDATA`

### 0.2.0 — Mods and saves
- Mod library: import mod zips (drag and drop), read `profile.xml`, install, update, remove
- Profile switcher with notes, author, version
- Per-profile save locations; save backup and restore (iCloud Drive optional)
- "Update available" for Community Updates and mods

### 0.3.0 — A real Mac app
- Fresh UI pass with bama design skills (mac-design, ux-design, design-system), app icon
- Game Mode: set `LSSupportsGameMode` / `LSApplicationCategoryType = games` in the patched Info.plist
- Controller support check (GameController framework) and mapping help
- Launcher self-update (Sparkle), signing and notarization
- Localization (reuse upstream language files where licensing allows)

### Later — Ideas to explore
- **Graphics:** window/fullscreen/integer-scale presets written to the game's config; CRT and
  palette shader options. Research whether an overlay layer can upscale the runner's output.
- **Metal renderer for Butterscotch**, then **MetalFX** spatial upscaling and CRT/pixel filters
  (only possible on the Butterscotch path; contribute upstream).
- **gmloader-style Android runner loader** as a second native route if Butterscotch falls short.
- **Randomizer:** integrate Randovania's AM2R support (generate seed → patch → launch).
- **Mod browser:** online catalog of community mods with one-click install.
- **Speedrun tools:** LiveSplit-style autosplitter / timer overlay.
- **Discord Rich Presence**, screenshot folder, playtime tracking per profile.
- **CLI / MCP** (bama:agent-cli) to install, launch, and manage mods from scripts.
- **Mod creation:** build a mod zip from a modified game (needs the Rust `data.win` tools).
