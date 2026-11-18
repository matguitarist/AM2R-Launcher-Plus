#!/bin/zsh
# Lists the GameMaker builtins a profile's game calls that the patched Butterscotch engine
# lacks, has only as a stub, or may fall back to a stub for, plus missing builtin variables.
# Run it after moving Butterscotch to a new commit or adding a profile (another version or a mod).
#
#   tools/builtin-coverage.sh <profile folder name (UUID)>
#
# Needs UndertaleModCli built in ~/Library/Developer/AM2RLauncherPlus/umt (dotnet build -c Release
# UndertaleModCli) and the engine source from tools/build-butterscotch.sh. Lists names only, never
# game code: AM2R is all rights reserved.
set -euo pipefail
uuid=${1:?usage: tools/builtin-coverage.sh <profile UUID>}
here=${0:A:h}
dev="$HOME/Library/Developer/AM2RLauncherPlus"
cli="$dev/umt/UndertaleModCli/bin/Release/net10.0/UndertaleModCli.dll"
src="$dev/engine/src/src"
game="$HOME/Library/Application Support/AM2RLauncherPlus/Profiles/$uuid/game.ios"
out=/tmp/AM2RLauncherPlus-coverage
[[ -f "$game" ]] || { echo "No profile $uuid"; exit 1; }
[[ -f "$cli" ]] || { echo "Build UndertaleModCli first ($cli)"; exit 1; }
[[ -f "$src/vm_builtins.c" ]] || { echo "Run tools/build-butterscotch.sh first"; exit 1; }
mkdir -p "$out"
# stdin closed: UndertaleModCli waits on a prompt otherwise.
OUT="$out/game.json" dotnet "$cli" load "$game" -s "$here/builtin-coverage/dump.csx" </dev/null >/dev/null
python3 -I "$here/builtin-coverage/compare.py" "$src" "$out/game.json" | tee "$out/report.txt"
