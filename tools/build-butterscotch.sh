#!/bin/zsh
# Builds the Butterscotch engine (AGPL-3.0) with our AM2R patches, for bundling (S-007).
# Output: ~/Library/Developer/AM2RLauncherPlus/engine/butterscotch and VERSION.
# Rebuilds only when the pinned commit or the patch changes.
set -euo pipefail
here=${0:A:h:h}
pin=$(cat "$here/Engine/BUTTERSCOTCH_COMMIT")
patch="$here/patches/butterscotch/all-current.patch"
work="$HOME/Library/Developer/AM2RLauncherPlus/engine"
src="$work/src"
out="$work/butterscotch"
stamp="$pin $(shasum -a 256 "$patch" | cut -c1-16)"

if [[ -x "$out" && -f "$work/VERSION" && "$(cat "$work/VERSION")" == "$stamp" ]]; then
  exit 0
fi
mkdir -p "$work"
if [[ ! -d "$src/.git" ]]; then
  git clone -q --filter=blob:none https://github.com/ButterscotchRunner/Butterscotch.git "$src"
fi
git -C "$src" fetch -q origin "$pin" 2>/dev/null || git -C "$src" fetch -q origin
git -C "$src" checkout -q --force "$pin"
git -C "$src" clean -qfdx -e build
git -C "$src" apply "$patch"
cmake -S "$src" -B "$src/build" -UPLATFORM -DBACKEND=appkit -DVIDEO_BACKEND=none -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 >/dev/null
cmake --build "$src/build" -j "$(sysctl -n hw.ncpu)" >/dev/null
cp "$src/build/butterscotch" "$out"
cp "$src/LICENSE" "$work/LICENSE"
echo "$stamp" > "$work/VERSION"
echo "built Butterscotch $stamp"
