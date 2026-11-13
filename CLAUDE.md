# AM2RLauncherPlus

A native macOS app in SwiftUI. It runs on this Mac only, with a local
SwiftData database and no server.

Shared rules for my Mac apps (build and check, design rules, skills, git):
@~/.claude/mac-app-conventions.md

## Layout

- `Sources/AM2RLauncherPlus/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/AM2RLauncherPlusKit/` rules and data logic with no SwiftUI. Tests in `Tests/AM2RLauncherPlusKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/AM2RLauncherPlus.app`, with Sparkle.framework embedded.
- Release: `tools/release.sh <version>` (settings in `release.conf`, version in `VERSION`). Use the mac-release skill.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## License

GPL-3.0-or-later (`LICENSE`). The bundled Butterscotch engine is AGPL-3.0 and ships as a separate executable with its source and our patches (`patches/butterscotch/`). Never add AM2R game files to this repo.
