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
  local input=$1 output=$2 abis=$3 actual bytes
  "$tools/apksigner" sign --ks "$GUCCIPLEXA_KEYSTORE" --ks-key-alias gucciplexa \
    --ks-pass env:GUCCIPLEXA_KEY_PASSWORD --out "$dst/$output" "$src/$input"
  "$tools/apksigner" verify --verbose "$dst/$output"
  actual=$("$tools/aapt" dump badging "$dst/$output")
  grep -F "package: name='com.gucciplexa.app'" <<< "$actual" >/dev/null
  grep -F "versionName='$version'" <<< "$actual" >/dev/null
  grep -Fx "native-code: $abis" <<< "$actual" >/dev/null
  bytes=$(wc -c < "$dst/$output")
  echo "$output: $bytes bytes"
  if (( bytes >= 100000000 )); then echo "APK must be under 100 MB" >&2; exit 1; fi
}
case "$variant" in
  android)
    for abi in arm64-v8a armeabi-v7a x86_64; do
      sign_apk "app-$abi-release.apk" "GucciPlexa-Android-$abi.apk" "'$abi'"
    done ;;
  firestick)
    sign_apk app-release.apk GucciPlexa-Firestick.apk "'arm64-v8a' 'armeabi-v7a'" ;;
  *) echo "Expected android or firestick" >&2; exit 2 ;;
esac
