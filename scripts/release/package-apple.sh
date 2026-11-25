#!/usr/bin/env bash
# Package the release product built by Flutter on this runner.
set -euo pipefail
platform=${1:?Specify ios or macos}
version=$(python3 scripts/pubspec_version.py --version-name pubspec.yaml)
build=$(python3 scripts/pubspec_version.py --build-number pubspec.yaml)
case "$platform" in
  ios) app=build/ios/iphoneos/GucciPlexa.app; plist=Info.plist ;;
  macos) app=build/macos/Build/Products/Release/GucciPlexa.app; plist=Contents/Info.plist ;;
  *) echo "Expected ios or macos" >&2; exit 2 ;;
esac
check_info() {
  local actual
  actual=$(/usr/libexec/PlistBuddy -c "Print :$1" "$app/$plist")
  if [[ "$actual" != "$2" ]]; then
    echo "$1 is $actual, expected $2" >&2
    exit 1
  fi
}
check_info CFBundleIdentifier com.gucciplexa.app
check_info CFBundleShortVersionString "$version"
check_info CFBundleVersion "$build"
mkdir -p build/distribution
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
if [[ "$platform" == ios ]]; then
  mkdir "$stage/Payload"
  ditto "$app" "$stage/Payload/GucciPlexa.app"
  output=build/distribution/GucciPlexa-iOS-unsigned.ipa
  ditto -c -k --norsrc --keepParent "$stage/Payload" "$stage/app.ipa"
  unzip -tq "$stage/app.ipa"
  mv "$stage/app.ipa" "$output"
else
  ditto "$app" "$stage/GucciPlexa.app"
  # The public build has no Developer ID credentials. Preserve the app's JIT entitlements.
  codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$stage/GucciPlexa.app"
  codesign --verify --deep --strict "$stage/GucciPlexa.app"
  ln -s /Applications "$stage/Applications"
  output=build/distribution/GucciPlexa-macOS.dmg
  hdiutil create -ov -format UDZO -volname GucciPlexa -srcfolder "$stage" "$output"
  hdiutil verify "$output"
fi
echo "$output"
