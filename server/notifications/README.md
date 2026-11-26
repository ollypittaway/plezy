# Offstage settings and notifications panel

One announcement goes to the recent list on every paired Offstage installation. An open app checks for announcements every 20 seconds and displays the newest one. The panel keeps the last 50 available in the app. Phones with push enabled also receive an operating-system alert while Offstage is in the background.

## Run on Coolify

1. Create an application from your copy of the repository. Choose the Dockerfile build pack, set the base directory to `/server/notifications`, the Dockerfile location to `/Dockerfile`, and the container port to `8080`. The same directory works as a standalone Docker build context.
2. Assign an HTTPS domain and a persistent volume at `/data`. Run a single replica. The SQLite database contains viewer preferences, announcements, device registrations, and the pending push queue. A volume created by Docker inherits the image directory’s ownership. For a bind mount, make the directory writable by UID 10001.
3. Generate an admin key with `openssl rand -hex 32` and put it in the runtime secret `ADMIN_KEY`. Deploy and sign into the panel with that key. The health check path is `/health`.
4. In the panel choose **Pair a device**. Paste its private link into **Offstage → Settings → Notifications** on each device. The pairing link allows reading announcements and registering for push. Keep the admin key with the sender.

The Offstage app attempts automatic device pairing with `https://panel.pittaway.dev` on first launch. On the official deployment, set the runtime variable `GUCCIPLEXA_AUTO_PAIR=true` to enable this. Any installation can then read app-wide announcements. Each installation receives an individual credential, and Plex identity verification is still required to sync settings. The setting **Settings → Notifications → Automatic device pairing** can be turned off. Other deployments use private pairing links unless they explicitly enable automatic enrollment.

In-app announcements work with just these settings. **Send notification** publishes immediately. The history shows whether Firebase accepted each push, whether it is queued for retry, or whether it failed. Firebase acceptance does not confirm that a person saw an alert.

## Enable iPhone and Android push

Use one Firebase project for the service and the mobile builds. The Android application ID and iOS bundle ID are both `com.offstage.app`. Register this identifier in Firebase and use matching client configuration files when enabling push for the new app.

- Enable the Firebase Cloud Messaging API. Give the service account permission to send FCM messages (Firebase Cloud Messaging API Admin). Mount its JSON credential as a read-only Coolify secret file, readable by UID 10001, and set `GOOGLE_APPLICATION_CREDENTIALS` to the container path. Restart the panel. That credential belongs on the server.
- **Android** — Register your app’s Android application ID in Firebase. Place the downloaded `google-services.json` at `android/app/google-services.json` before building. If you change the application ID, keep the Kotlin namespace intact. Test on a device with Google Play services.
- **iPhone** — Register your own iOS bundle ID in Firebase. Select your Apple Developer team and bundle ID on the Runner target. Enable Push Notifications on that App ID and use a provisioning profile with the matching entitlement. Add the downloaded `GoogleService-Info.plist` to the Runner target’s **Copy Bundle Resources** in Xcode. Upload your APNs authentication key, key ID, and team ID to Firebase under Project Settings → Cloud Messaging. Build and sign the app for that device.
- Pair the mobile build, enable **Mobile push notifications**, and grant the OS permission. Send a message while the app is open, then send another while it is backgrounded. OS notification settings also affect presentation. Turning off the switch removes that installation from future push deliveries. Desktop installations receive in-app announcements.

[Firebase Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) · [Firebase message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)

## Send from another web app

Call the panel from a trusted backend. Keep the admin key in that backend’s secrets. An optional `Idempotency-Key` lets the sender retry the same request safely. Reusing a key with different content returns HTTP 409.

```sh
curl --fail-with-body "$PANEL_URL/api/notifications" \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: new-releases-2026-11-25" \
  --data '{"title":"New releases","body":"The new films are ready to watch."}'
```

The first POST returns HTTP 201 and a message ID. A repeat returns HTTP 200 and the same ID. Maximum title length is 120 characters, body length is 1000, and their combined UTF-8 length is limited to 3000 bytes. Push retries have exponential backoff. A notification ID also serves as the device’s collapse identifier for retries.

## Local check

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m unittest -v
ADMIN_KEY="$ADMIN_KEY" DATA_DIR=./data BIND_ADDRESS=127.0.0.1 .venv/bin/python app.py
```

Open the local panel at [localhost on port 8080](http://localhost:8080). A phone needs the reachable HTTPS domain.

## Viewer settings sync

For a smaller image with settings sync and in-app announcements, set the Coolify build argument `INSTALL_FIREBASE=false`. Keep the default for mobile push.

The same container, HTTPS domain and SQLite volume serve the **Settings sync** and **Notifications** tabs. Pair each installation in **Settings → Notifications** using the private link from **Pair a device**. In **Settings → My profile**, choose **Enable sync** and confirm your panel's hostname. Each viewer uses their existing Plex sign-in. A local profile without a Plex identity can still change its settings offline.

The panel validates the active viewer's token with Plex over HTTPS, checks the switched Plex Home UUID when present, then issues a one-hour settings-only ticket. Plex tokens stay in memory during verification. The database stores a hashed viewer identifier, display name, preferences and last update. Only the admin key opens the dashboard. Keep the persistent volume and its backups private.

Sync runs after changes, on returning to the app, and every two minutes while it is open. A newly linked device adopts the saved profile. Offline edits are reconciled per setting after reconnection. If two devices change the same setting, the later successful upload wins. The shared settings include accent, library order and visibility, spoiler hiding, autoplay/countdown, default playback speed, intro and credit skipping, seek and resume distances, and subtitle size, colors, position, margins, bold and italic. Hardware decoding, HDR, local storage paths, and playback credentials stay on the device. Use **Sync now** to refresh immediately.
