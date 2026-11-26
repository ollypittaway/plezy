#!/usr/bin/env bash
# Package the APKs after Flutter has built this variant. The signing key lives outside the checkout.
set -euo pipefail
variant=${1:?Specify android or firestick}
: "${GUCCIPLEXA_KEYSTORE:?Missing release keystore path}"
: "${GUCCIPLEXA_KEY_PASSWORD:?Missing release keystore password}"
tools="${ANDROID_HOME:?}/build-tools/36.1.0"
src=build/app/outputs/flutter-apk
dst=build/distribution
mkdir -p "$dst"
version=$(python3 scripts/pubspec_version.py --version-name pubspec.yaml)
sign_apk() {
  local input=$1 output=$2 abis=$3 package_id=${4:-com.offstage.app} label=${5:-Offstage} actual bytes
  "$tools/apksigner" sign --ks "$GUCCIPLEXA_KEYSTORE" --ks-key-alias gucciplexa \
    --ks-pass env:GUCCIPLEXA_KEY_PASSWORD --out "$dst/$output" "$input"
  "$tools/apksigner" verify --verbose "$dst/$output"
  actual=$("$tools/aapt" dump badging "$dst/$output")
  grep -F "package: name='$package_id'" <<< "$actual" >/dev/null
  grep -Fx "application-label:'$label'" <<< "$actual" >/dev/null
  grep -F "versionName='$version'" <<< "$actual" >/dev/null
  grep -Fx "native-code: $abis" <<< "$actual" >/dev/null
  bytes=$(wc -c < "$dst/$output")
  echo "$output: $bytes bytes"
  if (( bytes >= 100000000 )); then echo "APK must be under 100 MB" >&2; exit 1; fi
}
case "$variant" in
  android)
    for abi in arm64-v8a armeabi-v7a x86_64; do
      sign_apk "$src/app-$abi-release.apk" "Offstage-Android-$abi.apk" "'$abi'"
    done ;;
  firestick)
    sign_apk "$src/app-release.apk" Offstage-Firestick.apk "'arm64-v8a' 'armeabi-v7a'" ;;
  migration)
    sign_apk "${2:?Specify the migration APK path}" Offstage-Firestick-Migration.apk "'arm64-v8a' 'armeabi-v7a'" com.gucciplexa.app "Offstage (previous install)" ;;
  *) echo "Expected android, firestick or migration" >&2; exit 2 ;;
esac
