#!/usr/bin/env bash
set -euo pipefail

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ ]]
tag="v$RELEASE_VERSION"
repo="$GITHUB_REPOSITORY"
case "$RELEASE_PLATFORM" in
  android) assets=(Offstage-Android-arm64-v8a.apk Offstage-Android-armeabi-v7a.apk Offstage-Android-x86_64.apk) ;;
  # The updater advances when the regular APK appears. Have the migration APK ready first.
  firestick) assets=(Offstage-Firestick-Migration.apk Offstage-Firestick.apk) ;;
  ios) assets=(Offstage-iOS-unsigned.ipa) ;;
  macos) assets=(Offstage-macOS.dmg) ;;
  windows) assets=(Offstage-Windows-Setup.exe) ;;
  *) exit 1 ;;
esac
for asset in "${assets[@]}"; do
  test -s "$asset"
done

# Reserve a draft only once this job actually has an installer to publish.
release_id=$(gh api --paginate "repos/$repo/releases?per_page=100" |
  jq -sr --arg tag "$tag" 'add | map(select(.tag_name == $tag)) | if length > 1 then error("duplicate release tag") else .[0].id // empty end')
if [[ -z "$release_id" ]]; then
  notes="$RUNNER_TEMP/release-notes.md"
  cat > "$notes" <<'NOTES'
Packages are published as each platform finishes. Android and Fire OS APKs are signed. For a new Fire TV installation, download Offstage-Firestick.apk. Fire TV v0.0.23 can migrate using its in-app updater. On earlier releases, open firestick.offstage.download in Downloader to install Offstage directly. The iPhone IPA requires external signing. The Mac disk image is ad hoc signed and the Windows installer is unsigned.
NOTES
  printf '\n<!-- offstage-release-run:%s -->\n' "$GITHUB_RUN_ID" >> "$notes"
  gh release create "$tag" --repo "$repo" --verify-tag --draft --title "Offstage $RELEASE_VERSION" --notes-file "$notes"
  release_id=$(gh release view "$tag" --repo "$repo" --json databaseId --jq .databaseId)
fi
remote_assets="repos/$repo/releases/$release_id/assets?per_page=100"
inventory=$(gh api "$remote_assets")

upload() {
  local file="$1" status
  status=$(jq -r --arg name "$file" '.[] | select(.name == $name) | if .state == "uploaded" and .size > 0 then "complete" else "incomplete" end' <<< "$inventory")
  case "$status" in
    complete) return ;;
    incomplete) gh release upload "$tag" --repo "$repo" --clobber "$file" ;;
    '') gh release upload "$tag" --repo "$repo" "$file" ;;
    *) return 1 ;;
  esac
}

for asset in "${assets[@]}"; do upload "$asset"; done
# A retry may have built different bytes. Hash the files that users will download.
inventory=$(gh api "$remote_assets")
manifest="SHA256SUMS-$RELEASE_PLATFORM.txt"
for asset in "${assets[@]}"; do
  digest=$(jq -er --arg name "$asset" '.[] | select(.name == $name and .state == "uploaded" and .size > 0) | .digest' <<< "$inventory")
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]
  printf '%s  %s\n' "${digest#sha256:}" "$asset"
done > "$manifest"
upload "$manifest"
if [[ $(gh api "repos/$repo/releases/$release_id" --jq .draft) == true ]]; then
  gh release edit "$tag" --repo "$repo" --draft=false
fi
