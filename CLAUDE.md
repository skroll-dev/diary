# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication Style

- **When writing or editing code:** Communicate like **Captain Jean-Luc Picard** — decisive, precise, authoritative. Short commands. "Make it so." No hedging. Confidence in every line.
- **When giving advice, recommendations, or discussing trade-offs:** Communicate like **Counselor Deanna Troi** — empathetic, thoughtful, attuned to the bigger picture. Help the user feel the implications of a decision, not just the technical facts.

## Project Overview

**AI Tagebuch** (codename: Mein KI-Tagebuch) — a privacy-first, AI-powered voice diary app for the DACH market. Users dictate diary entries; the backend transcribes audio and generates structured diary entries with mood tags and follow-up questions via Gemini. All data stays in the EU.

- **Firebase project:** `diary-6fa61`
- **Bundle ID:** `com.diary.app`
- **Target platforms:** iOS (min 15.0), Android, Web (full recording support via WebSocket streaming)

## Commands

### Flutter App

```bash
cd flutter
flutter pub get
dart run build_runner build          # regenerate .g.dart files after schema/provider changes
flutter run                          # iOS/Android on connected device
flutter run -d chrome                # Web
flutter analyze
flutter test
flutter test test/path/to/test.dart
flutter build web --release --dart-define=PROXY_BASE_URL=https://...
flutter build apk
flutter build ios
```

### Backend Services

Each service has its own Python venv (3.12+ required; 3.14 works with `pydantic>=2.11.0`).

```bash
cd ai-proxy              # or gdpr-export

# macOS / Linux
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
LOG_FILE=../log/ai-proxy.log .venv/bin/uvicorn app.main:app --reload --port 8080

# Windows
python -m venv .venv && .venv\Scripts\pip install -r requirements.txt
.venv\Scripts\uvicorn app.main:app --reload --port 8080

# gdpr-export (port 8081, same pattern)
```

**Logs:** ai-proxy writes to `log/ai-proxy.log` (controlled by `LOG_FILE` env var). The `log/` directory at repo root must exist — create it once with `mkdir log`.

#### ai-proxy `.env` (gitignored, local dev only)

```env
ENV=development        # bypasses Firebase App Check; omit or set to 'production' in Cloud Run
GCP_PROJECT=diary-6fa61
GCP_REGION=europe-west1
GOOGLE_APPLICATION_CREDENTIALS=./credentials.json   # service account key for local auth
LOG_FILE=../log/ai-proxy.log
LOG_LEVEL=debug        # debug | info | warning | error
```

The service account key JSON lives at `ai-proxy/credentials.json` (gitignored — matched by `*credentials*.json`). Download it from GCP Console → IAM → Service Accounts → Keys → Add Key. In Cloud Run, `GOOGLE_APPLICATION_CREDENTIALS` is not needed — the service account is attached to the revision directly.

### Deployment (CI/CD)

GitHub Actions auto-deploy on push to `main`:
- `ai-proxy/` changes → Cloud Run (`europe-west3`) via `.github/workflows/deploy-ai-proxy.yml`
- `flutter/` changes → Firebase Hosting via `.github/workflows/deploy-web.yml`

Required GitHub repository secrets: `WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT`, `FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_OPTIONS_DART`, `PROXY_BASE_URL`.

```bash
# Manually update Cloud Run env vars
gcloud run services update ai-proxy --region=europe-west3 --project=diary-6fa61 \
  --update-env-vars=ENV=development   # bypasses App Check for testing
```

### Firebase

```bash
# Install flutterfire CLI (once per machine)
dart pub global activate flutterfire_cli
# Add $HOME/.pub-cache/bin (macOS) or %LOCALAPPDATA%\Pub\Cache\bin (Windows) to PATH

firebase login   # required before flutterfire configure

# Regenerate firebase_options.dart after Firebase project changes
cd flutter && flutterfire configure --project=diary-6fa61 --platforms=android,ios,web
```

## Architecture

### System Design

```
Flutter App (iOS/Android/Web)
  └─► Firebase Auth (anonymous, user identity)
  └─► ai-proxy (Cloud Run, europe-west3)
  │     POST /transcribe/        (native) audio blob → Chirp 3
  │     WS   /transcribe/ws      (web) PCM16 stream → WAV chunks → Chirp 3
  │     POST /entries/normalize  → Vertex AI Gemini 2.5 Flash
  │     POST /entries/generate   → Vertex AI Gemini 2.5 Flash (Prompt A)
  │     POST /entries/merge      → Vertex AI Gemini 2.5 Flash (Prompt B)
  │     audio bytes processed in RAM, never persisted
  └─► Cloud Firestore (eu-eur3, entries per user)
  └─► Drift (SQLite, local source of truth)

gdpr-export (Cloud Run) ──► Firestore (JSON export / account deletion)
```

### Flutter App (`flutter/lib/`)

Flutter 3.44.1+ (Dart 3.12+) required — `record ^7.0.0` needs Dart SDK `^3.12.0`. Riverpod 3 + GoRouter 17, Material Design 3 (seed `#4A90D9`), offline-first via Drift (SQLite).

#### Routes

| Path | Screen | GoRouter `extra` |
|---|---|---|
| `/` | `RecordingScreen` | `RecordingContext?` (defaults to `FreshRecording`) |
| `/topics` | `TopicsReviewScreen` | `TopicsArgs` (named record — see below) |
| `/entry/:date` | `EntryScreen` | — |
| `/history` | `HistoryScreen` | — |
| `/analytics` | `AnalyticsScreen` | — |

Shell navigation (Heute / Verlauf / Analyse) is handled by `StatefulShellRoute.indexedStack` in `app_router.dart`, rendered by `shared/widgets/main_shell.dart`.

`TopicsArgs` (defined in `app_router.dart`):
```dart
typedef TopicsArgs = ({
  String date, String duration,
  List<TopicDto> topics, String normalizedTranscript,
  String bodyMarkdown, String mood, double moodScore,
  List<String> followUpQuestions, String transcriptReason,
});
```

#### Recording Flow

The primary user journey is `/` → `/topics` → `/entry/:date`.

**`RecordingContext`** (`features/recording/recording_context.dart`) — sealed class for `/` route `extra`:
- `FreshRecording` — default, first recording of the day
- `ExtendingTopic({topicTitle, followUpHint?})` — answer to a follow-up question or topic deepening
- `ContinuingEntry` — general continuation, AI decides which topic(s) it belongs to

**Navigation model — critical:**
- `context.push()` for: recording→topics, topics→entry. Stacks screens so back works.
- `context.go('/')` for: "Von vorne anfangen" — resets the entire stack.
- **Continuations (Ergänzen, Antworten):** show a `ModalBottomSheet` overlay on `TopicsReviewScreen` — the user never navigates away from the diary screen. The overlay uses `RecordingControls` from `shared/widgets/recording_controls.dart`.
- After a continuation recording, `TopicsReviewScreen` owns the merge pipeline and updates its own state in place.

**RecordingScreen** handles the **first recording of the day only**. It does not manage continuation state (`_hasExistingEntry` etc. have been removed).

**Recording pipeline** (`_stopRecording` in `recording_screen.dart`):

*Web path:*
1. `RecordingService.start()` → starts PCM16 stream
2. `ProxyClient.transcribeWebSocket(stream)` → WebSocket to `/transcribe/ws`
3. `RecordingService.stopStream()` → signals `"done"` to server
4. WebSocket future resolves with raw transcript

*Native path:*
1. `RecordingService.stopAndRead()` → audio file bytes
2. `ProxyClient.transcribe(audio)` → HTTP POST `/transcribe/`

*Both paths continue:*
3. `ProxyClient.normalize(transcript)` → cleaned text
4. `ProxyClient.generateEntry(normalized)` → `EntryDto` (bodyMarkdown, mood, moodScore, followUpQuestions, topics)
5. `EntryRepository.saveEntry(...)` → Drift + Firestore sync (best-effort, unawaited)
6. `context.push('/topics', extra: TopicsArgs(...))`

**Continuation pipeline** (inside `TopicsReviewScreen._runMergePipeline`):
1. `ProxyClient.normalize(rawTranscript)` → normalized
2. `ProxyClient.mergeEntry(existingBody, normalized, previousQuestions)` → updated `EntryDto`
3. `setState(...)` — UI updates immediately with new topics/questions
4. `EntryRepository.mergeEntry(...)` — DB sync, fire-and-forget (must not block UI)

#### Data model — Drift schema v2

**Entries table:**
- Core: `id`, `userId`, `date`, `bodyMarkdown`, `mood`, `moodScore`, `durationSeconds`, `language`, `version`, `createdAt`, `updatedAt`, `synced`
- Added in v2: `followUpQuestions` (JSON string), `topics` (JSON string)

**RawTranscripts table:**
- Core: `id`, `entryId`, `content` (raw STT — never shown to user), `createdAt`
- Added in v2: `normalizedContent` (user-editable, the primary display text), `reason` (`'initial'` | `'followUp:<hint>'` | `'continuation'`)

`EntryRepository` methods: `saveEntry`, `mergeEntry`, `updateEntry`, `updateTranscript`, `deleteTranscript`, `getTranscriptsForDate`.

Always run `dart run build_runner build` after changing `app_database.dart`.

#### Shared widgets

`shared/widgets/recording_controls.dart` — `RecordingControls` (ConsumerStatefulWidget) + `WaveformPainter`. Handles recording start/stop, waveform animation, timer, transcription (web WS + native HTTP), processing state. Calls `onComplete(String rawTranscript)` when done. Used by both `RecordingScreen` and the `TopicsReviewScreen` overlay.

`shared/widgets/main_shell.dart` — `MainShell` wraps `StatefulNavigationShell` (GoRouter) with a slide-from-bottom entrance animation. Hosts `_NavBar` (3 items: Heute/mic, Verlauf/history, Analyse/bar_chart) with `_NavItem` animated via `TweenAnimationBuilder<Color?>`, `AnimatedScale`, and `AnimatedDefaultTextStyle`. Haptic feedback on tab tap.

#### TopicsReviewScreen — Living Diary Entry

The screen is the **Tageseintrag** — the growing diary entry for the day. Key design:
- **Aufnahmen section** (collapsed by default): shows `normalizedContent` of each recording with provenance label. Tap to edit (triggers re-derivation via `generateEntry`). Long-press to delete (same).
- **Themen section**: topic cards with full chapter `text`, follow-up hint, and `Ergänzen` button per topic.
- **Mein KI-Tagebuch fragt section**: general follow-up questions as tappable mic invitations.
- **General Ergänzen button**: records without topic context — AI decides placement.
- **Recording overlay**: `ModalBottomSheet` with `RecordingControls` + context chip.
- **Von vorne anfangen**: overflow menu `⋮` only — never in the main scroll area.
- `bodyMarkdown` is cached for merge calls but NOT displayed here (belongs on EntryScreen).

Re-derivation (transcript edit/delete): concatenates all `normalizedContent` in order → `generateEntry` → `updateEntry`. UI updates before DB save (DB is best-effort).

#### Key architectural rules
- Drift (SQLite) is the local source of truth; Firestore syncs in background
- UI state always updates before awaiting DB/network operations — never block UI on DB save
- `authServiceProvider` warmup is guarded with `if (!kIsWeb)` in `main.dart`
- `ProxyClient` skips `Authorization` header when `_baseUrl` contains `localhost`
- `record` package web path: `AudioEncoder.pcm16bits` only — all other encoders throw at runtime
- `TopicDto.text` is complete chapter prose — never truncated or summarized

#### Current implementation state

| Screen | State |
|---|---|
| `RecordingScreen` | Complete — real audio pipeline, web + native |
| `TopicsReviewScreen` | Complete — Living Diary design, overlay continuations, transcript edit/delete, merge pipeline |
| `EntryScreen` | Skeleton ("IN PROGRESS") |
| `HistoryScreen` | Complete — sticky Year/Month headers (`flutter_sticky_header: ^0.8.0`), 10-year mock data, right-side scroll scrubber (`_ScrollScrubber` / `_ScrubberPainter` CustomPainter with year ticks + month dots, tap + drag support) |
| `AnalyticsScreen` | Skeleton ("Kommt bald" placeholder) |
| `settings/` | Folder exists, no route wired yet |

### ai-proxy (`ai-proxy/app/`)

FastAPI service. All routes require `X-Firebase-AppCheck` header (verified by `services/auth.py`). Set `ENV=development` on the service to bypass App Check for testing.

| Route | Description |
|---|---|
| `POST /transcribe/` | Audio (m4a/aac/wav, max 10 MB) → raw transcript via Chirp 3 |
| `WS /transcribe/ws` | PCM16 stream + `"done"` sentinel → WAV-wrapped chunks → Chirp 3 |
| `POST /entries/normalize` | Raw transcript → cleaned text via Gemini |
| `POST /entries/generate` | Transcript → entry JSON: `body_markdown`, `mood`, `mood_score`, `follow_up_questions`, `topics[{title, text, follow_up_hint}]` |
| `POST /entries/merge` | Existing entry body + new transcript → updated entry JSON (same schema) |
| `GET /health` | Liveness check |

**Speech-to-Text:** Chirp 3 (`chirp_3`), location `eu`, endpoint `eu-speech.googleapis.com`. The `_` default recognizer requires `locations/eu` — `europe-west3`, `europe-west4`, and `global` are all rejected.

**Gemini model:** `gemini-2.5-flash`, `temperature=0.7`, `max_output_tokens=8192`, JSON output mode. The AI persona is named **Mein KI-Tagebuch**. Topic `text` fields must be complete chapter prose — never truncated.

**Logging:** All Gemini calls logged at `info` level: `gemini_call` (fn, input) and `gemini_response` (fn, finish_reason, output_tokens, output). JSON parse errors log the full raw response via `gemini_json_parse_error`.

### gdpr-export (`gdpr-export/app/`)

FastAPI service for DSGVO compliance: exports all user Firestore data as a JSON ZIP, or deletes the account and all associated Firestore documents.

### Agent Skills

Skills in `.claude/skills/`. **Before writing code for a relevant domain, read the matching `SKILL.md` first.**

Key skills:
- `firebase-firestore` — mandatory for any Firestore work (security rules, queries, indexes)
- `flutter-apply-architecture-best-practices` — Riverpod + layered architecture patterns
- `cloud-run-basics` — deploying/updating Cloud Run services
- `gemini-api` — Vertex AI / Gemini SDK patterns
- `ui-ux-pro-max` — design system, color/typography, UX patterns (invoke via `/ui-ux-pro-max` skill)

## Key Constraints

- **GDPR / DSGVO:** Speech-to-Text uses Chirp 3 at `eu-speech.googleapis.com` (EU multi-region). All other GCP resources must stay in `europe-west3` or `eu-eur3`. Audio is processed in RAM only — never written to disk or object storage.
- **Firebase App Check** is required on all ai-proxy routes in production. Anonymous auth must be enabled in the Firebase console (`diary-6fa61` → Authentication → Sign-in method).
- **Web audio:** `kIsWeb` must gate any `local_auth` usage. The `record` package works on web, but only `AudioEncoder.pcm16bits` is supported for streaming.
- **`firebase_options.dart`** is gitignored (contains API keys). Regenerate with `flutterfire configure` after cloning.
- **Drift schema changes** require a migration in `app_database.dart` (`MigrationStrategy.onUpgrade`) and `dart run build_runner build` afterwards. Current schema version: **2**.
