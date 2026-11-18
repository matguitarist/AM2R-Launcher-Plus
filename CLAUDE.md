# AM2RLauncherPlus

A native macOS app in SwiftUI. It runs on this Mac only, with a local
SwiftData database and no server.

Shared rules for my Mac apps (build and check, design rules, skills, git):
@~/.claude/mac-app-conventions.md

Shared rules for how every project is laid out and named:
@~/.claude/project-layout.md

## Layout

- `Sources/AM2RLauncherPlus/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/AM2RLauncherPlusKit/` rules and data logic with no SwiftUI. Tests in `Tests/AM2RLauncherPlusKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/AM2RLauncherPlus.app`, with Sparkle.framework embedded.
- Release: `tools/release.sh <version>` (settings in `release.conf`, version in `VERSION`). Use the mac-release skill.
- `tools/builtin-coverage.sh <profile UUID>` lists the GameMaker builtins a profile's game calls that the patched engine lacks or stubs (UndertaleModCli in `~/Library/Developer/AM2RLauncherPlus/umt`). Run it after moving Butterscotch or adding a mod. Names only, never game code.
- `tools/engine-check.sh <profile UUID>` checks a new engine build before shipping: missing builtins, in-game checks (`tools/engine-check/checks.gml`, injected into a scratch copy of the game), a Metroid fight (`metroid.gml`: a missile must hurt an Alpha Metroid), and a playthrough (title, new game, F12, a few steps) compared with reference frames kept in `~/Library/Developer/AM2RLauncherPlus/engine-check/reference`. Run it after `tools/build-butterscotch.sh`; `--update-references` after you looked at changed frames.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## License

GPL-3.0-or-later (`LICENSE`). The bundled Butterscotch engine is AGPL-3.0 and ships as a separate executable with its source and our patches (`patches/butterscotch/`). Never add AM2R game files to this repo.
