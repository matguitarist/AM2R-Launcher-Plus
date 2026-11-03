# Engine

AM2R Launcher Plus plays the game with [Butterscotch](https://github.com/ButterscotchRunner/Butterscotch),
an open-source GameMaker runner (AGPL-3.0), built natively for Apple silicon.

- `BUTTERSCOTCH_COMMIT`: the upstream commit we build.
- `../patches/butterscotch/all-current.patch`: our changes on top of it (also offered upstream).
- `Info.plist`: the helper app `AM2R.app` inside the launcher (`Contents/Helpers/AM2R.app`).
- `tools/build-butterscotch.sh` clones, patches and builds it; `build.sh` bundles it with its
  license, the commit and the patch, so the corresponding source ships with every build.
