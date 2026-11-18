#!/bin/zsh
# Checks the patched Butterscotch engine against a Community Updates profile before you ship it:
#   1. builtins: nothing the game calls is missing, apart from the known Android and debug ones;
#   2. in-game checks: tools/engine-check/checks.gml runs inside a scratch copy of the game;
#   3. Metroid fight: a missile fired into an Alpha Metroid hurts it (tools/engine-check/metroid.gml);
#   4. playthrough: title, new game, intro skip, F12, a few steps, compared with reference frames.
#
#   tools/engine-check.sh <profile folder name (UUID)> [--update-references]
#
# Run after tools/build-butterscotch.sh, when Butterscotch moves or a patch changes. The first run
# (or --update-references, after you looked at the frames) saves the reference frames in
# ~/Library/Developer/AM2RLauncherPlus/engine-check/reference; they show the game, so they stay
# out of the repo. Needs UndertaleModCli in ~/Library/Developer/AM2RLauncherPlus/umt (step 2).
# Exit 0 when everything passes. The real profile and saves are never touched.
set -euo pipefail
uuid=${1:?usage: tools/engine-check.sh <profile UUID> [--update-references]}
update=${2:-}
here=${0:A:h}
dev="$HOME/Library/Developer/AM2RLauncherPlus"
engine="$dev/engine/butterscotch"
cli="$dev/umt/UndertaleModCli/bin/Release/net10.0/UndertaleModCli.dll"
profile="$HOME/Library/Application Support/AM2RLauncherPlus/Profiles/$uuid"
refs="$dev/engine-check/reference"
out=/tmp/AM2RLauncherPlus-enginecheck
frames=(500 1000 2000 3190)
[[ -f "$profile/game.ios" ]] || { echo "No profile $uuid"; exit 1; }
[[ -x "$engine" ]] || { echo "Build the engine first: tools/build-butterscotch.sh"; exit 1; }
rm -rf "$out"; mkdir -p "$out"
failed=0
fail() { echo "FAIL $*"; failed=1; }

echo "== 1. Builtins"
unknown=$(cd "$profile" && "$engine" --headless --print-unknown-functions game.ios 2>&1 | sed -n 's/^- //p' | sort)
expected=$(grep -v '^#' "$here/engine-check/known-missing.txt" | sort)
new=$(comm -23 <(echo "$unknown") <(echo "$expected"))
if [[ -n "$new" ]]; then fail "the game calls builtins the engine lacks: $(echo $new | tr '\n' ' ')"; else echo "PASS only the known Android and debug builtins are missing"; fi

echo "== 2. In-game checks"
if [[ -f "$cli" ]]; then
  cp -R "$profile" "$out/checks"
  GML="$here/engine-check/checks.gml" dotnet "$cli" load "$out/checks/game.ios" -s "$here/engine-check/inject.csx" \
    -o "$out/checks/game.ios" -f </dev/null > "$out/inject.log" 2>&1
  grep -q COMPILED "$out/inject.log" || { cat "$out/inject.log"; fail "checks.gml didn't compile"; }
  mkdir -p "$out/checks-saves"
  (cd "$out/checks" && "$engine" --save-folder "$out/checks-saves" --exit-at-frame 30 --speed 10 game.ios > "$out/checks.log" 2>&1) || fail "the engine stopped during the checks (see $out/checks.log)"
  sed -n 's/^Game: CHECK //p' "$out/checks.log"
  passes=$(grep -c "^Game: CHECK PASS" "$out/checks.log" || true)
  (( passes == $(grep -c '"CHECK ' "$here/engine-check/checks.gml") )) || fail "only $passes in-game checks passed"
else
  echo "SKIP no UndertaleModCli at $cli"
fi

echo "== 3. Metroid fight"
if [[ -f "$cli" ]]; then
  cp -R "$profile" "$out/metroid"
  EVENT="oCharacter:DrawGUI" GML="$here/engine-check/metroid.gml" dotnet "$cli" load "$out/metroid/game.ios" \
    -s "$here/engine-check/inject.csx" -o "$out/metroid/game.ios" -f </dev/null > "$out/metroid-inject.log" 2>&1
  grep -q COMPILED "$out/metroid-inject.log" || { cat "$out/metroid-inject.log"; fail "metroid.gml didn't compile"; }
  mkdir -p "$out/metroid-saves"
  (cd "$out/metroid" && "$engine" --headless --save-folder "$out/metroid-saves" --seed 1 --playback-inputs "$here/engine-check/play.json" \
    --exit-at-frame 3300 game.ios > "$out/metroid.log" 2>&1) || fail "the engine stopped during the Metroid fight (see $out/metroid.log)"
  sed -n 's/^Game: CHECK //p' "$out/metroid.log"
  passes=$(grep -c "^Game: CHECK PASS" "$out/metroid.log" || true)
  (( passes == $(grep -c '"CHECK ' "$here/engine-check/metroid.gml") )) || fail "only $passes Metroid fight checks passed"
else
  echo "SKIP no UndertaleModCli at $cli"
fi

echo "== 4. Playthrough"
mkdir -p "$out/play-saves"
shots=(); for f in $frames; do shots+=(--screenshot-at-frame $f); done
(cd "$profile" && "$engine" --save-folder "$out/play-saves" --seed 1 --playback-inputs "$here/engine-check/play.json" \
  --exit-at-frame 3200 --speed 10 --screenshot "$out/frame.%d.png" $shots game.ios > "$out/play.log" 2>&1) || fail "the engine stopped during the playthrough (see $out/play.log)"
snap="$out/play-saves/snap/snap 0000.png"
if [[ -f "$snap" ]] && file "$snap" | grep -q "320 x 240"; then echo "PASS F12 saved a 320 x 240 screenshot"; else fail "F12 saved no screenshot"; fi
mkdir -p "$refs"
for f in $frames; do
  actual="$out/frame.$f.png"
  [[ -f "$actual" ]] || { fail "no frame $f"; continue; }
  if [[ "$update" == "--update-references" || ! -f "$refs/frame.$f.png" ]]; then
    cp "$actual" "$refs/frame.$f.png"; echo "SAVED reference frame $f"
  elif result=$(python3 -I "$here/engine-check/compare_png.py" "$actual" "$refs/frame.$f.png"); then
    echo "PASS frame $f matches the reference"
  else
    fail "frame $f $result (compare $actual with $refs/frame.$f.png)"
  fi
done

echo
if (( failed )); then echo "Engine check FAILED. Files in $out"; exit 1; fi
echo "Engine check passed."
