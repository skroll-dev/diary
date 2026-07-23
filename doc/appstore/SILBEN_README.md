# Silben

A Flutter-based German word puzzle game where players drag syllables ("Silben") to form words on a crossword-style puzzle board.

**Platforms:** Android, iOS, Web, macOS, Linux, Windows

## Game Overview

![gamescreen overview image](doc\concept\images\gamescreen1.png)

The game screen has three sections:

- **SilbenPuzzle** — crossword grid showing the words to find; solved syllables fly here when a word is completed
- **SilbenSortierer** — drop zone where the player assembles syllables into a word via drag & drop
- **SilbenBank** — bottom bar with all available source syllables to drag from

Players progress through themed worlds (e.g. "Badeurlaub"), each with background music and increasing difficulty, unlocking the next world after completing the final level.

## Build & Run

```bash
# Install dependencies
flutter pub get

# Production (Welcome → Level selection → Game)
flutter run -t lib/main.dart

# Development / Lab mode
flutter run -t lib/main2.dart

# Web on local network
flutter run -t lib/main2.dart -d web-server --web-port 8080 --web-hostname 0.0.0.0

# Run tests
flutter test
```

**VS Code launch configs:** `silben` (production) · `Labor` (development)

## Deployment

Hosted at: https://syllables-978768655003.europe-west1.run.app/

## Release Builds

### Before building either platform

1. **Bump the version** in `pubspec.yaml` — format is `{version}+{build}`, e.g. `1.0.4+4`. Both numbers must increase with each store submission.
2. **Disable test ads** in `lib/config/ad_config.dart`:
   ```dart
   static const bool useTestAds = false;
   ```
   Re-enable after the build (`true` is the safe default for development).

---

### Android

**Prerequisites:** `android/key.properties` must exist (not committed to git):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

The keystore lives at `doc/certs/android/upload-keystore.jks`.

**Build:**

```bash
flutter build appbundle
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Upload the `.aab` to [Google Play Console](https://play.google.com/console) → Production (or Internal/Closed testing track).

**Test on device before uploading:**

```bash
flutter run --release -d 00008110-000C74CC3AE2401E   # Simon's device
```

---

### iOS

**Prerequisites:**
- Xcode with a valid Apple Developer account signed in
- Signing certificates and provisioning profiles configured in Xcode
- `ios/Runner/GoogleService-Info.plist` present

**Steps:**

1. Build the release artefact:
   ```bash
   flutter build ios --release
   ```

2. Open the Xcode workspace:
   ```bash
   open ios/Runner.xcworkspace
   ```

3. In Xcode: **Product → Archive**

4. In the Organizer that opens: click **Distribute App**

5. Select **App Store Connect**, then confirm with **Distribute**

6. Open [App Store Connect](https://appstoreconnect.apple.com/) to review the build and submit it for review / promote to production

---

### Links

| Resource | URL |
|---|---|
| Developer home | https://skroll-dev.github.io |
| Ads verification | https://skroll-dev.github.io/app-ads.txt |
| Privacy policy | https://skroll-dev.github.io/privacy-policy.html |
| Terms | https://skroll-dev.github.io/terms.html |