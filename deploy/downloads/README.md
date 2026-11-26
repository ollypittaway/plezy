# Offstage releases

The **Offstage packages** workflow builds a versioned GitHub Release when a maintainer pushes to `tofa-redesign`. The Coolify service redirects each platform hostname to an asset in the latest public release. GitHub serves the files, so Coolify does not need storage for packages or a GitHub token.

Fire TV updater requests to `firestick.offstage.download/releases/latest` receive GitHub release metadata cached for three minutes. The v0.0.23 updater sees the migration APK under the filename they recognize and its real SHA-256 digest. The router sends its version-specific request to the signed migration APK on the same GitHub release. New installations use the regular `Offstage-Firestick.apk`. The bare hostname remains the Downloader install link.

| Download hostname | Release asset |
| --- | --- |
| `firestick.offstage.download` (also `firestick.pittaway.dev`) | `Offstage-Firestick.apk`, one package for 32-bit and 64-bit ARM Fire OS devices |
| `android.offstage.download` (also `android.pittaway.dev`) | `Offstage-Android-arm64-v8a.apk`, for current ARM64 phones |
| `ios.offstage.download` (also `ios.pittaway.dev`) | `Offstage-iOS-unsigned.ipa`, for importing into an iOS signing service |
| `win.offstage.download` (also `windows.offstage.download` and `windows.pittaway.dev`) | `Offstage-Windows-Setup.exe`, one installer for x64 and ARM64 |
| `mac.offstage.download` (also `mac.pittaway.dev`) | `Offstage-macOS.dmg`, containing Offstage and a shortcut to Applications |

Android also serves `/armeabi-v7a` and `/x86_64`. Every hostname serves `/SHA256SUMS.txt`. The Firestick build targets Fire OS, which installs APKs. Vega OS requires a separate port.

## First install with the new package ID

Offstage uses `com.offstage.app` on Android, Fire OS and Apple devices. Archived releases through v0.0.23 carry Offstage filenames but still install under the previous package ID. Once a new release includes both Fire TV APKs and this router is deployed, open the release-signed v0.0.23 app, choose **Update now**, confirm the Fire OS update, then open the updated app and choose **Install Offstage**. Confirm the installation and open the new app. Both APKs must use the same release signing certificate as the installed copy. The migration build continues to play media if the user dismisses the offer. The new app requires sign-in and offline downloads stay with the original installation.

For any public Fire TV release before v0.0.23, or a build with a different signing certificate, open `firestick.offstage.download` in Downloader once the new Offstage APK is published. Install Offstage directly. There is no intermediate v0.0.23 installation. The updaters in releases v0.0.3 through v0.0.22 check GitHub directly and require the previous APK filename. Future releases update the new app in place.

All download redirects use the Offstage filenames, including version-specific Fire TV links. Redeploy the download router after pushing this configuration. Existing platform hostnames can continue to use their current DNS records when they already point to Coolify.

## Configure signing once

Android and Fire OS use the same persistent release key. Back up both files from the private directory printed by the key setup script. These files are excluded from Git. A test build and a release build with the same package ID must have matching signatures for an in-place update. Uninstalling an app clears its local settings and downloads.

On the Mac where the key was generated, run this from the repository root if the two GitHub secrets still need configuring:

```sh
gh auth login
scripts/release/android-release-key.sh upload ollypittaway/plezy
```

The uploader configures the encrypted keystore and password secrets, preserving any already present. Only a new signing setup needs `scripts/release/android-release-key.sh init`. On another machine building updates, restore the original key from your backup.

The iOS asset needs signing for the intended devices before installation. The Mac app is ad hoc signed and distributed without Apple notarization. The Windows installer is unsigned and Windows may display a publisher prompt.

## Publish a release

GitHub Actions must be enabled in the fork. A push to `tofa-redesign` starts the workflow, which assigns a version and build number and tags the source. A manual workflow run can produce Actions artifacts for testing.

Open **Actions → Offstage packages**. Each platform publishes independently to the same release as soon as its package is ready. The first successful publisher makes the release public. Existing binaries are preserved on retries. Platform-specific SHA-256 manifests are uploaded alongside packages; SHA256SUMS.txt becomes available after all platforms publish. During a partial release, download URLs for unfinished platforms (and the combined checksum manifest) may return 404. On a branch, a manual workflow run produces downloadable Actions artifacts. GitHub shows the manual dispatch button once the workflow is present on the default branch.

The download routes pick up each new public release automatically.

If a runner or workflow needs a fix after a release tag is pushed, commit the workflow fix and push that commit to `release-build/v0.0.1` (substitute the intended version). The workflow on that branch resolves the existing release tag once and builds its exact source commit on every platform. This keeps the published tag stable.

## Connect the five domains in Coolify

1. Choose a **Docker Compose** application from the public repository `https://github.com/ollypittaway/plezy` on the branch containing this folder.
2. Set **Base Directory** to `/deploy/downloads` and **Docker Compose Location** to `/compose.yml`.
3. Assign the HTTPS hostnames in the table to the **downloads** service on container port **8080**. For a Coolify field that accepts a URL with a destination port, use `https://firestick.offstage.download:8080`. The public URL is `https://firestick.offstage.download`. [Coolify domain routing](https://coolify.io/docs/core/networking/domains)
4. Deploy. The health endpoint is `/healthz`. After the release is published, `curl -fIL https://firestick.offstage.download/` should reach the APK with a successful final response. Use the same check on the other download hostnames.

The live **Offstage Downloads** application uses Coolify’s **Dockerfile** build pack with base directory `/deploy/downloads`, Dockerfile location `/Dockerfile`, and port `8080`. Both build packs use the same nginx configuration.

The release repository must stay public for anonymous downloads. If the fork is renamed or moved, update the repository URL in `default.conf` and redeploy the router.
