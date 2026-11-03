#!/bin/zsh
# Releases AM2R Launcher Plus (S-032): Developer ID build with the hardened runtime, a notarized DMG,
# a Sparkle appcast signed with the launcher's EdDSA key, and a GitHub release that holds both.
#
# Usage: tools/release.sh 0.2.0            build, notarize, publish
#        tools/release.sh 0.2.0 --local    build and notarize only; nothing is pushed or published
#
# Once per Mac:
#   xcrun notarytool store-credentials AM2RLauncherPlus --apple-id <your Apple ID> --team-id 434NVXAGUS
#   (asks for an app-specific password from account.apple.com)
# The EdDSA private key is in the login Keychain, account "am2rlauncherplus" (Sparkle's generate_keys).
# Back it up: generate_keys --account am2rlauncherplus -x <file>. Without it, no update can be published.
set -euo pipefail
here=${0:A:h:h}
version=${1:?usage: tools/release.sh <version> [--local]}
local_only=0
[[ " $* " == *" --local "* ]] && local_only=1
repo="matguitarist/AM2R-Launcher-Plus"
name="AM2RLauncherPlus"
notary_profile="AM2RLauncherPlus"
sparkle_bin="$HOME/Library/Developer/$name/build/artifacts/sparkle/Sparkle/bin"
out="$HOME/Library/Developer/$name/release/$version"
dmg="$out/$name-$version.dmg"

[[ $version =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "version must look like 1.2.3"; exit 1; }
[[ -z "$(git -C "$here" status --porcelain)" ]] || { echo "commit your changes first"; exit 1; }
identity=$(security find-identity -v -p codesigning | grep -m1 '"Developer ID Application' | awk '{print $2}' || true)
[[ -n "$identity" ]] || { echo "no Developer ID Application certificate in the Keychain"; exit 1; }
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 \
  || { echo "no notary credentials: run xcrun notarytool store-credentials $notary_profile (see the top of this script)"; exit 1; }

# 1. Build and sign with Developer ID, hardened runtime and a secure timestamp.
echo "$version" > "$here/VERSION"
SIGN_IDENTITY=$identity SIGN_OPTIONS="--options runtime --timestamp" "$here/build.sh"
app="$HOME/Applications/$name.app"
codesign --verify --deep --strict "$app"

# 2. The DMG: the app and a link to Applications.
rm -rf "$out"; mkdir -p "$out"
staging=$(mktemp -d)
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "AM2R Launcher Plus" -srcfolder "$staging" -ov -format UDZO "$dmg"
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$dmg"

# 3. Notarize and staple, so it opens without warnings.
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature -v "$dmg"

# 4. The appcast: one item, the newest release, signed with the launcher's key.
signature=$("$sparkle_bin/sign_update" --account am2rlauncherplus "$dmg")
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app/Contents/Info.plist")
notes=$(git -C "$here" log --format='<li>%s</li>' "$(git -C "$here" describe --tags --abbrev=0 2>/dev/null || git -C "$here" rev-list --max-parents=0 HEAD)..HEAD" | sed 's/&/\&amp;/g')
cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AM2R Launcher Plus</title>
    <item>
      <title>$version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>$notes</ul>]]></description>
      <enclosure url="https://github.com/$repo/releases/download/v$version/$name-$version.dmg" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
XML
echo "built $dmg and $out/appcast.xml"
if (( local_only )); then
  git -C "$here" checkout -- VERSION 2>/dev/null || true
  exit 0
fi

# 5. Publish: commit the version, tag, push, and make the GitHub release with the DMG and the appcast.
git -C "$here" commit -q -m "Release $version" -- VERSION || true
git -C "$here" tag "v$version"
git -C "$here" push -q origin HEAD "v$version"
gh release create "v$version" "$dmg" "$out/appcast.xml" --repo "$repo" --title "AM2R Launcher Plus $version" \
  --notes "$(git -C "$here" log --format='- %s' "$(git -C "$here" describe --tags --abbrev=0 "v$version^" 2>/dev/null || git -C "$here" rev-list --max-parents=0 HEAD)..v$version^")"
echo "released v$version: https://github.com/$repo/releases/tag/v$version"
