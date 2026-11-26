#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(git rev-parse --show-toplevel)
dir="$root/.gucciplexa-signing"
case "${1:-}" in
  init)
    if [[ -e "$dir" ]]; then
      echo "Signing directory already exists at $dir. Keep the existing key for updates." >&2
      exit 1
    fi
    keytool_bin=keytool
    studio_keytool="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
    if [[ -x "$studio_keytool" ]]; then keytool_bin="$studio_keytool"; fi
    mkdir "$dir"
    # Only promote complete credentials. A failed run leaves no partial identity.
    trap 'rm -f "$dir"/{release.p12,password}; rmdir "$dir"' ERR
    openssl rand -hex 32 > "$dir/password"
    "$keytool_bin" -genkeypair -storetype PKCS12 -keystore "$dir/release.p12" \
      -storepass:file "$dir/password" -keypass:file "$dir/password" -alias gucciplexa \
      -keyalg RSA -keysize 3072 -validity 10950 -dname "CN=Offstage Android Release"
    echo "Created $dir. Back up both files privately."
    ;;
  upload)
    repository=${2:?Provide the owner/repository that will build Offstage}
    [[ -s "$dir/password" && -s "$dir/release.p12" ]]
    if ! command -v gh >/dev/null; then echo "Install GitHub CLI and sign in to upload the secrets." >&2; exit 1; fi
    # Resume a partial upload without changing a signing identity already configured in GitHub.
    names=$(gh secret list --repo "$repository" --json name --jq '.[].name')
    if ! grep -Fxq GUCCIPLEXA_ANDROID_KEYSTORE <<< "$names"; then
      openssl base64 -A -in "$dir/release.p12" | gh secret set GUCCIPLEXA_ANDROID_KEYSTORE --repo "$repository"
    fi
    if ! grep -Fxq GUCCIPLEXA_ANDROID_PASSWORD <<< "$names"; then
      gh secret set GUCCIPLEXA_ANDROID_PASSWORD --repo "$repository" < "$dir/password"
    fi
    ;;
  *) echo "Usage: $0 init | upload OWNER/REPO" >&2; exit 2 ;;
esac
