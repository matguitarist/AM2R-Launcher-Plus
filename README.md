# AM2R Launcher Plus

A native Mac app for Apple silicon that turns your own copy of AM2R 1.1 into the latest
[Community Updates](https://github.com/AM2R-Community-Developers) release and plays it natively,
without Rosetta.

- **Install:** drop `AM2R_11.zip` (or its folder) on the window. The app checks that it's the real 1.1,
  downloads the Mac patch data, and patches it with a built-in xdelta decoder. No other tools needed.
- **Play natively:** the game runs on [Butterscotch](https://github.com/ButterscotchRunner/Butterscotch),
  an open-source GameMaker runner, built for Apple silicon. Each profile can fall back to the official
  runner with Rosetta.
- **Per-profile settings:** display, scanline and CRT filters, a Mac-friendly controller layout, and
  the game language, right under the Play button.
- **Stay current:** the Play page shows when a newer Community Updates release exists, and Update
  patches it into the same profile while keeping your saves and settings. The launcher itself updates
  with Sparkle.
- **Profiles:** rename, duplicate, show in Finder and delete, optionally keeping the saves. The data
  folder can live on another drive.

## Requirements

- A Mac with Apple silicon and macOS 26 or later.
- Your own copy of AM2R 1.1. **This project contains no AM2R game files** and never downloads them.

## Install

Download the DMG from [Releases](https://github.com/matguitarist/AM2R-Launcher-Plus/releases), open
it, and drag AM2R Launcher Plus to Applications.

## Build from source

```sh
./build.sh --open        # builds, signs and installs ~/Applications/AM2RLauncherPlus.app
swift test --scratch-path ~/Library/Developer/AM2RLauncherPlus/test-build
```

`build.sh` also clones, patches and builds Butterscotch (`tools/build-butterscotch.sh`).

## License

AM2R Launcher Plus is free software under the GNU General Public License v3.0 or later (`LICENSE`).

The bundled engine, Butterscotch, is AGPL-3.0 and ships as a separate executable inside the app
(`Contents/Helpers/AM2R.app`). The app carries its license, the upstream commit (`Engine/BUTTERSCOTCH_COMMIT`)
and our patch (`patches/butterscotch/`), so its corresponding source comes with every build.

AM2R (Another Metroid 2 Remake) is a fan game by DoctorM64. The Community Updates and the Mac patch
data are by the AM2R Community Developers. This launcher is an unofficial, independent project, not
affiliated with them or with Nintendo.
