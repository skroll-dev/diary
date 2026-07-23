# Running on Android

The app has run on Web only so far. This is the setup for running it natively on Android for the first time — emulator or physical device.

## Fixed before this could work

**`applicationId`/`namespace` mismatch (fixed 2026-07-23):** `android/app/build.gradle.kts` declared `com.ai.diary.app`, but `google-services.json` and `MainActivity.kt` (`android/app/src/main/kotlin/com/diary/app/MainActivity.kt`) both use `com.diary.app` — the real bundle ID (matches iOS, see `CLAUDE.md`). With the mismatch, `Firebase.initializeApp()` would have crashed on launch with "No matching client found for package name". Both `namespace` and `applicationId` in `build.gradle.kts` now read `com.diary.app`.

**Missing microphone permission request (fixed 2026-07-23):** `RecordingService.start()` (`recording_service.dart`) called `_recorder.start()`/`startStream()` directly without ever requesting `RECORD_AUDIO`. On Web this never mattered (the browser handles its own mic prompt), but on Android nothing was ever asking, so `AudioRecord` failed to initialize (`AudioFlinger could not create record track, status: -1`). Native `start()` now calls `await _recorder.hasPermission()` first and throws `RecordingPermissionDenied` if refused; both call sites (`recording_screen.dart`, `recording_controls.dart`) catch it and show a snackbar instead of crashing the pipeline.

**Silent-but-valid recordings — empty transcript every time (fixed 2026-07-24):** After fixing the permission issue, recordings on a Samsung Galaxy S9+ produced a properly-sized, playable `.m4a` file (confirmed via `adb pull` + `ffprobe`/`ffplay` — real speech, correct duration, `probe_score=100`), yet `/transcribe/` always returned `{"transcript": "", "duration_seconds": 0.0}`. Isolated by feeding the exact same file straight to the Speech-to-Text v2 API (bypassing the app and Cloud Run entirely): Chirp 3's `AutoDetectDecodingConfig` silently returns zero results for the AAC-in-MP4 container this device's hardware encoder produces (no error — it just doesn't decode it), while the identical audio re-muxed to WAV/PCM transcribes correctly. Native recording (`recording_service.dart`) now uses `AudioEncoder.wav` instead of `AudioEncoder.aacLc`, sidestepping the container-detection issue entirely — matching what the Web path already does with PCM16. Trade-off: WAV is uncompressed, so file size scales with duration (~1.9 MB/min at 16 kHz mono) against `/transcribe/`'s 10 MB cap — fine for typical diary-entry lengths, but a very long recording could hit that ceiling where AAC wouldn't have.

## Prerequisites

- Android Studio + an emulator image, **or** a physical device with USB debugging enabled
- `flutter doctor` shows no blocking Android toolchain issues
- `android/app/google-services.json` already exists in this repo and already contains a `com.diary.app` client — no `flutterfire configure` needed just to get Android running

## Backend reachability

`ProxyClient`'s `PROXY_BASE_URL` default (`proxy_client.dart`) now points at the deployed Cloud Run instance:

```
https://ai-proxy-918937960824.europe-west3.run.app
```

so a plain `flutter run` on an emulator or physical device reaches the real backend with no local networking setup (no `10.0.2.2`, no LAN IP, no `uvicorn --host 0.0.0.0`). That endpoint runs without `ENV=development`, so `verify_app_check` (`ai-proxy/app/services/auth.py` — despite the name, it just verifies a Firebase Auth ID token, not real App Check) enforces auth on every route. `ProxyClient._dio()` only skips sending the `Authorization` header when the base URL contains `localhost`/`127.0.0.1`; against the remote URL it always attaches `Bearer <Firebase ID token>`, and anonymous auth warms up automatically on native launch (`main.dart`, `!kIsWeb` branch), so this works out of the box.

`GDPR_EXPORT_BASE_URL` (`gdpr_export_client.dart`) still defaults to `http://localhost:8081` — no remote `gdpr-export` URL has been wired in yet. That only matters for the Profile screen's export/delete-account actions; the core recording pipeline doesn't touch it.

To point at a **local** ai-proxy instead (e.g. testing an unreleased backend change), the old local-networking rules still apply since `localhost` means the device itself on Android:

| Target | Correct host |
|---|---|
| Android emulator | `10.0.2.2` (maps to host machine) |
| Physical device, same Wi-Fi as your Mac | your Mac's LAN IP (`ipconfig getifaddr en0`) |

```bash
# start ai-proxy reachable from outside the host
LOG_FILE=../log/ai-proxy.log .venv/bin/uvicorn app.main:app --reload --port 8080 --host 0.0.0.0

# emulator
flutter run -d emulator-5554 --dart-define=PROXY_BASE_URL=http://10.0.2.2:8080

# physical device
flutter run -d <device-id> --dart-define=PROXY_BASE_URL=http://192.168.x.x:8080
```

## First run

```bash
cd flutter
flutter pub get
flutter devices                 # confirm the emulator/device shows up
flutter run -d <device-id>      # uses the remote ai-proxy by default
```

Anonymous Firebase Auth warms up automatically on non-web launch (`main.dart` — `authServiceProvider` is read on `initState` when `!kIsWeb`), so the app should reach the recording screen without any manual sign-in.

## What to verify on first native run

- **Microphone permission prompt appears** — `record_android` merges `RECORD_AUDIO` into the manifest automatically, but this is the first time it'll actually be exercised on this platform; confirm the OS permission dialog shows up and recording produces a real waveform.
- **Recording pipeline uses the native path** — `recording_service.dart` branches on `kIsWeb`; native records AAC-LC to a temp file (`stopAndRead()` → `POST /transcribe/`), not the Web WebSocket/PCM16 path. Confirm a full recording → transcribe → normalize → generate round-trip works.
- **Deep link intent filter** — `AndroidManifest.xml` already declares an `https://diary-6fa61.firebaseapp.com/__/auth/links` intent filter for email-link sign-in; this only matters if you test the email sign-in flow.

## Release signing

Set up 2026-07-23, mirroring the `Silben` project's pattern. `android/key.properties` (gitignored, not committed):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

The keystore lives at `doc/certs/android/upload-keystore.jks` (gitignored via `doc/certs/` in the root `.gitignore` — that path wasn't covered by `android/.gitignore`'s `*.jks` rule since it sits outside the `android/` directory). `build.gradle.kts` reads `key.properties` at the `android/` project root and wires a `release` signing config from it; if `key.properties` is missing, `buildTypes.release` falls back to the debug key so `flutter run --release` still works without release signing configured.

**Build:**

```bash
flutter build appbundle
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Upload the `.aab` to [Google Play Console](https://play.google.com/console).

**Back up the keystore + password somewhere outside this repo (password manager, etc.).** There is no recovery path — losing either means you can never publish an update to this app under its existing Play Store listing again.

**Sideloading (no Play Store, e.g. an old device that rejects `.aab`):** build an APK instead — `.aab` is a Play Store publishing format only and isn't directly installable.

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Uses the same `release` signing config as `build appbundle`. If install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, uninstall any existing debug-signed copy first. If it fails with `INSTALL_FAILED_OLDER_SDK`, the device is below `flutter.minSdkVersion`.
