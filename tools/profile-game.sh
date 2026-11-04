#!/bin/zsh
# Plays a profile on a profiling build of the engine and reports where the frame time goes.
# The real saves stay untouched: the game runs on a copy in /tmp.
#
#   tools/profile-game.sh <profile folder name (UUID)>
#
# Play to the slow spot, stay a while, then quit the game. The report lands in
# /tmp/AM2RLauncherPlus-profile/report.txt: frames over 20 ms, and every 300 frames the GML
# scripts that took the most time.
# Set BUTTERSCOTCH_FILTER=scanlines or crt to measure with the display filter the profile uses.
set -euo pipefail
uuid=${1:?usage: tools/profile-game.sh <profile UUID> [engine options]}; shift
data="$HOME/Library/Application Support/AM2RLauncherPlus"
src="$HOME/Library/Developer/AM2RLauncherPlus/engine/src"
engine="$src/build-profile/butterscotch"
profile="$data/Profiles/$uuid"
out=/tmp/AM2RLauncherPlus-profile
[[ -f "$profile/game.ios" ]] || { echo "No profile $uuid"; exit 1; }

if [[ ! -x "$engine" || "$src/build/butterscotch" -nt "$engine" ]]; then
  echo "Building the profiling engine…"
  cmake -S "$src" -B "$src/build-profile" -UPLATFORM -DBACKEND=appkit -DVIDEO_BACKEND=none \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DENABLE_VM_GML_PROFILER=ON >/dev/null
  cmake --build "$src/build-profile" -j "$(sysctl -n hw.ncpu)" >/dev/null
fi

rm -rf "$out"
mkdir -p "$out"
cp -R "$data/Saves/$uuid" "$out/saves" 2>/dev/null || mkdir -p "$out/saves"
cd "$profile"
"$engine" --save-folder "$out/saves" --profile-gml-scripts 300 --trace-frames "$@" "$profile/game.ios" > "$out/engine.log" 2>&1 || true

{
  echo "== Slow frames (game + present over 16.7 ms)"
  sed -nE 's/.*Frame ([0-9]+) \((End|Present), ([0-9.]+) ms\).*/\1 \2 \3/p' "$out/engine.log" |
    awk '$2 == "End" { game[$1] = $3 } $2 == "Present" { if (game[$1] + $3 > 16.7) printf "frame %s: game %.2f ms, present %.2f ms\n", $1, game[$1], $3 }' | head -200
  echo
  echo "== Averages"
  sed -nE 's/.*Frame [0-9]+ \((End|Present), ([0-9.]+) ms\).*/\1 \2/p' "$out/engine.log" |
    awk '{ n[$1]++; s[$1] += $2; if ($2 > m[$1]) m[$1] = $2 } END { for (k in n) printf "%s: average %.2f ms, worst %.2f ms over %d frames\n", (k == "End" ? "game" : "present"), s[k] / n[k], m[k], n[k] }' 
  echo
  echo "== Heaviest GML scripts per 300 frames"
  grep -v "Frame [0-9]* (" "$out/engine.log" | grep -A25 "ms/frame" | head -600
} > "$out/report.txt"
echo "Report: $out/report.txt ($(grep -c "(End," "$out/engine.log" || true) frames traced)"
