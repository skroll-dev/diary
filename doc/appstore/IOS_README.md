# Releasing to the App Store (iOS)

Manual release flow via Xcode Organizer — no Fastlane, no CI. Mirrors the manual signing/distribution style already used for Android (see `ANDROID_README.md`), adapted to Apple's tooling.

## Prerequisites

- Xcode with a valid Apple Developer Program account signed in (Xcode → Settings → Accounts)
- Signing certificates and provisioning profiles configured for `com.diary.skroll.app` — either "Automatically manage signing" in the Runner target's Signing & Capabilities tab (simplest), or a manually maintained Distribution certificate + App Store provisioning profile
- `flutter/ios/Runner/GoogleService-Info.plist` present (gitignored — pull from Firebase Console → Project Settings → iOS app, or `flutterfire configure`; without it `Firebase.initializeApp()` crashes on launch)
- An App Store Connect app record already created for `com.diary.skroll.app` (App Store Connect → My Apps → +)
- Bump `version` in `flutter/pubspec.yaml` (`<versionName>+<versionCode>`, e.g. `0.4.18+26`) — the build number must be higher than the last one uploaded for this bundle ID, or App Store Connect rejects the upload

## Steps

1. **Build the release artefact:**

   ```bash
   cd flutter
   flutter build ios --release
   ```

2. **Open the Xcode workspace** (never `Runner.xcodeproj` directly — CocoaPods integration requires the workspace):

   ```bash
   open ios/Runner.xcworkspace
   ```

3. In Xcode, select **Any iOS Device (arm64)** as the run destination (Archive is disabled while a simulator is selected), then **Product → Archive**.

4. When the archive finishes, the **Organizer** window opens automatically (or Window → Organizer). Select the new archive and click **Distribute App**.

5. Choose **App Store Connect** as the distribution method, then **Upload** (not "Export"), and confirm through the remaining prompts (automatic signing / re-signing options can be left at their defaults unless managing certificates manually). Click **Distribute** to upload.

6. **Open App Store Connect** ([appstoreconnect.apple.com](https://appstoreconnect.apple.com)) → the app → TestFlight or App Store tab. The build appears after Apple finishes processing (usually a few minutes, sometimes longer for the "Missing Compliance" export-compliance prompt — answer it once per version). From there, attach the build to a version and **submit for review**, or promote an already-approved build to production.

## Notes

- **Export compliance:** App Store Connect will ask whether the app uses encryption beyond what's exempt (standard HTTPS/TLS counts as exempt). This app only uses standard TLS to Firebase/Cloud Run, so answer "No" / select the HTTPS-only exemption unless that changes.
- **Build number collisions:** re-running `flutter build ios --release` without bumping `pubspec.yaml`'s `+<n>` produces a build App Store Connect will reject as a duplicate — bump it before every archive, not just before every submission.
- **Signing errors in step 3:** almost always an expired/missing Distribution certificate or provisioning profile for `com.diary.skroll.app` — check Xcode → Settings → Accounts → your team → Manage Certificates, or let "Automatically manage signing" regenerate it.
