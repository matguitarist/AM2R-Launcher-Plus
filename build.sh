#!/bin/zsh
# Builds AM2RLauncherPlus and installs it to ~/Applications/AM2RLauncherPlus.app.
# Build products live in ~/Library/Developer/AM2RLauncherPlus, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="AM2RLauncherPlus"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  # Sign by fingerprint: two certificates with the same name make the name ambiguous.
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 '"Apple Development: ' | awk '{print $2}' || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
# Version from VERSION (tools/release.sh sets it); the build number is the date, so it always grows (Sparkle compares it).
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__VERSION__/$(cat "$here/VERSION")/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# Package resources (LogKit's viewer strings): Bundle.module finds them in Contents/Resources.
for bundle in "$scratch/$config"/*.bundle(N); do cp -R "$bundle" "$app/Contents/Resources/"; done
# Sparkle (launcher updates, S-032), next to the executable's @executable_path/../Frameworks rpath.
mkdir -p "$app/Contents/Frameworks"
cp -R "$scratch/$config/Sparkle.framework" "$app/Contents/Frameworks/"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
# The game engine: Butterscotch (AGPL-3.0) as the helper app AM2R.app, with its source pointers (S-007).
"$here/tools/build-butterscotch.sh"
engine="$HOME/Library/Developer/$name/engine"
helper="$app/Contents/Helpers/AM2R.app"
mkdir -p "$helper/Contents/MacOS" "$helper/Contents/Resources" "$app/Contents/Resources/Engine"
cp "$engine/butterscotch" "$helper/Contents/MacOS/butterscotch"
cp "$here/Engine/Info.plist" "$helper/Contents/Info.plist"
[[ -f "$here/Resources/AppIcon.icns" ]] && cp -X "$here/Resources/AppIcon.icns" "$helper/Contents/Resources/"
cp "$engine/LICENSE" "$app/Contents/Resources/Engine/LICENSE"
cp "$engine/VERSION" "$app/Contents/Resources/Engine/VERSION"
cp "$here/patches/butterscotch/all-current.patch" "$app/Contents/Resources/Engine/butterscotch-am2r.patch"
cp "$here/Engine/README.md" "$app/Contents/Resources/Engine/README.md"
xattr -cr "$app"
# Inside out: Sparkle's helpers, the framework, the engine, then the app. SIGN_OPTIONS adds the hardened runtime for releases.
sign() { codesign --force ${=SIGN_OPTIONS:-} --sign "$identity" "$@" 2>&1 | grep -v "replacing existing signature" || true; }
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc" "$sparkle/Autoupdate" "$sparkle/Updater.app"; do
  [[ -e "$item" ]] && sign "$item"
done
sign "$app/Contents/Frameworks/Sparkle.framework"
codesign --force ${=SIGN_OPTIONS:-} --sign "$identity" "$helper" 2>&1 | grep -v "replacing existing signature" || true
codesign --force ${=SIGN_OPTIONS:-} --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
