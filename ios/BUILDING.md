# Build Offstage for iPhone

The iOS app builds as `Offstage.app` with bundle identifier `com.offstage.app`. It supports iOS 15.5 and later. iOS treats the new identifier as a separate installation, so expect to sign in again.

## Prepare your Mac

Install Xcode, open it once, and install iOS platform support when prompted. Install Flutter **3.47.1** and CocoaPods. Run the following from the repository root.

```sh
flutter --version
flutter doctor -v
flutter precache --ios
flutter pub get --enforce-lockfile --no-example
flutter build ios --config-only --no-codesign
(cd ios && pod install --deployment)
open ios/Runner.xcworkspace
```

For setup on a new Mac, see the [Flutter SDK archive](https://docs.flutter.dev/install/archive) and [Flutter iOS setup guide](https://docs.flutter.dev/platform-integration/ios/setup).

## Run on a simulator

In Xcode’s toolbar, choose the **Runner** scheme and an iPhone simulator. Press **⌘R**. The simulator installs Offstage without an Apple Developer account.

If Xcode reports `Module 'universal_gamepad' not found`, close the standalone `Runner.xcodeproj` window and open `ios/Runner.xcworkspace`. If the workspace was already open and shows **No Scheme**, close and reopen it after closing the project. The Project navigator (**⌘1**) should list both **Runner** and **Pods**. Build again with **⌘B**.

## Install on your iPhone

1. Connect the iPhone to your Mac, unlock it and trust the Mac. On iOS 16 or later, enable **Settings → Privacy & Security → Developer Mode** if prompted.
2. In **Xcode → Settings → Accounts**, add your Apple Account. Select the blue **Runner** project in the navigator, then **Runner** under **Targets**.
3. Open **Signing & Capabilities**, enable **Automatically manage signing** and choose your own **Team**. Check that the bundle identifier reads `com.offstage.app`. Apple must accept the identifier for your team before Xcode can install a signed build.
4. The project includes a push-notification entitlement. If you are using a free **Personal Team** and Xcode reports a provisioning error for Push Notifications, go to the Runner target’s **Build Settings**, expand **Code Signing Entitlements**, and clear the **Debug** value for your local device build. For a push-enabled build, use an Apple Developer Program team with Push Notifications enabled for this app ID.
5. Choose your connected iPhone in Xcode’s toolbar and press **⌘R**. Look for **Offstage** on its Home Screen.

Apple documents pairing, signing and Developer Mode in [Running your app on a device](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## Export an IPA for AppHost

AppHost creates the installation link for an IPA you have already signed. To share Offstage with registered iPhones, sign in to Xcode with your Apple Developer Program team and register each phone’s UDID. In `ios/Runner.xcworkspace`, select **Runner → Signing & Capabilities**, enable **Automatically manage signing**, and select that team for the Release configuration. The app ID is `com.offstage.app`. [AppHost](https://appho.st/) · [Apple’s ad hoc provisioning guide](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile)

From the project root, run `flutter build ipa --release --export-method ad-hoc`. After Flutter reports a successful IPA export, upload the freshly exported file from `build/ios/ipa/` to AppHost. Its package inspector should list the intended device UDIDs and the provisioning profile’s expiration date.

## Build a release

To check the device release build locally, run the following from the repository root.

```sh
flutter build ios --release --no-codesign
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' build/ios/iphoneos/Offstage.app/Info.plist
```

The second command should print `com.offstage.app`. This artifact is unsigned. To share a beta, select a distribution-capable team and the **Any iOS Device** destination in Xcode, then use **Product → Archive → Distribute App → App Store Connect**. Use an App Store Connect record registered to the same bundle identifier and invite testers through TestFlight. The signed command-line equivalent for creating an archive and IPA is `flutter build ipa --release`. [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios)
