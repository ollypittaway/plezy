# GucciPlexa releases

The **GucciPlexa packages** workflow builds a GitHub Release when a maintainer pushes a tag matching the version in the project’s pubspec. The Coolify service redirects each platform hostname to an asset in the latest public release. GitHub serves the files, so Coolify does not need storage for packages or a GitHub token.

| Download hostname | Release asset |
| --- | --- |
| `firestick.pittaway.dev` | `GucciPlexa-Firestick.apk`, one package for 32-bit and 64-bit ARM Fire OS devices |
| `android.pittaway.dev` | `GucciPlexa-Android-arm64-v8a.apk`, for current ARM64 phones |
| `ios.pittaway.dev` | `GucciPlexa-iOS-unsigned.ipa`, for importing into an iOS signing service |
| `windows.pittaway.dev` | `GucciPlexa-Windows-Setup.exe`, one installer for x64 and ARM64 |
| `mac.pittaway.dev` | `GucciPlexa-macOS.dmg`, containing GucciPlexa and a shortcut to Applications |

Android also serves `/armeabi-v7a` and `/x86_64`. Every hostname serves `/SHA256SUMS.txt`. The Firestick build targets Fire OS, which installs APKs. Vega OS requires a separate port.

## Configure signing once

Android and Fire OS use the same persistent release key. Back up the private `.gucciplexa-signing/` directory in a secure place outside this checkout. These files are excluded from Git. The previously shared test APKs used a different signing key. Moving from a test-signed copy to the first release requires removing the test app, which clears its local settings and downloads. Future updates signed with the release key can install in place.

On the Mac where the key was generated, run this from the repository root if the two GitHub secrets still need configuring:

```sh
gh auth login
scripts/release/android-release-key.sh upload ollypittaway/plezy
```

The uploader leaves existing repository secrets in place. A new signing setup can generate its first identity with `scripts/release/android-release-key.sh init`. On another machine building updates, restore the original key from your backup. To configure secrets manually, use **Settings → Secrets and variables → Actions**. Store the single-line base64 PKCS#12 as `GUCCIPLEXA_ANDROID_KEYSTORE` and its password as `GUCCIPLEXA_ANDROID_PASSWORD`.

The iOS asset needs signing for the intended devices before installation. The Mac app is ad hoc signed and distributed without Apple notarization. The Windows installer is unsigned and Windows may display a publisher prompt.

## Publish 0.0.1

The first version is `0.0.1+161`. The public version starts at 0.0.1 and the internal build number continues from 160. GitHub Actions must be enabled in the fork. Once the local release commit and tag are ready, the maintainer can publish both refs together:

```sh
git push --atomic origin tofa-redesign refs/tags/v0.0.1
```

Open **Actions → GucciPlexa packages**. The release job waits for every platform, calculates SHA-256 checksums, uploads the complete asset set to a draft and makes it public. A failed upload can resume from that draft. A published release keeps its existing binaries on a retry. On a branch, a manual workflow run produces downloadable Actions artifacts. GitHub shows the manual dispatch button once the workflow is present on the default branch.

For subsequent releases, update both version components in `pubspec.yaml`, commit, and tag that commit with the public version prefixed by `v`. Push the branch and that tag. The existing Coolify routes pick up the new public release automatically.

If a runner or workflow needs a fix after a release tag is pushed, commit the workflow fix and push that commit to `release-build/v0.0.1` (substitute the intended version). The workflow on that branch resolves the existing release tag once and builds its exact source commit on every platform. This keeps the published tag stable.

## Connect the five domains in Coolify

1. Choose a **Docker Compose** application from the public repository `https://github.com/ollypittaway/plezy` on the branch containing this folder.
2. Set **Base Directory** to `/deploy/downloads` and **Docker Compose Location** to `/compose.yml`.
3. Assign each of the five HTTPS hostnames in the table to the **downloads** service, using container port **8080**. For a Coolify field that accepts a URL with a destination port, use e.g. `https://firestick.pittaway.dev:8080`. The public URL is `https://firestick.pittaway.dev`. [Coolify domain routing](https://coolify.io/docs/core/networking/domains)
4. Deploy. The health endpoint is `/healthz`. After the release is published, `curl -fIL https://firestick.pittaway.dev/` should reach the APK with a successful final response. Use the same check on the other four hostnames.

The live **GucciPlexa Downloads** application uses Coolify’s **Dockerfile** build pack with base directory `/deploy/downloads`, Dockerfile location `/Dockerfile`, and port `8080`. Both build packs use the same nginx configuration.

The release repository must stay public for anonymous downloads. If the fork is renamed or moved, update the repository URL in `default.conf` and redeploy the router.
