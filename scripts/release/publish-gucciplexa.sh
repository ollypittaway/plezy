#!/usr/bin/env bash
set -euo pipefail
version=$(python3 scripts/pubspec_version.py --version-name pubspec.yaml)
tag="v$version"
[[ "${GITHUB_REF:?}" == "refs/tags/$tag" ]]
cd build/distribution
assets=(GucciPlexa-{Android-arm64-v8a.apk,Android-armeabi-v7a.apk,Android-x86_64.apk,Firestick.apk,iOS-unsigned.ipa,Windows-Setup.exe,macOS.dmg})
for asset in "${assets[@]}"; do
  if [[ ! -s "$asset" ]]; then echo "Missing release asset: $asset" >&2; exit 1; fi
done
sha256sum "${assets[@]}" > SHA256SUMS.txt
gh_opts=(--repo "${GITHUB_REPOSITORY:?}")
if state=$(gh release view "$tag" "${gh_opts[@]}" --json isDraft --jq .isDraft); then
  if [[ "$state" == false ]]; then
    echo "Release $tag is already public. Use a new version for new binaries."
    exit 0
  fi
else
  gh release create "$tag" "${gh_opts[@]}" --verify-tag --draft --title "GucciPlexa $version" \
    --notes 'Android and Fire OS APKs are signed. The iPhone IPA is for an external signing service. The Mac disk image is ad hoc signed and the Windows installer is unsigned.'
fi
gh release upload "$tag" "${gh_opts[@]}" --clobber "${assets[@]}" SHA256SUMS.txt
gh release edit "$tag" "${gh_opts[@]}" --draft=false
