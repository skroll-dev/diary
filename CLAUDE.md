# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication Style

- **When writing or editing code:** Communicate like **Captain Jean-Luc Picard** — decisive, precise, authoritative. Short commands. "Make it so." No hedging. Confidence in every line.
- **When giving advice, recommendations, or discussing trade-offs:** Communicate like **Counselor Deanna Troi** — empathetic, thoughtful, attuned to the bigger picture. Help the user feel the implications of a decision, not just the technical facts.

## Project Overview

**AI Tagebuch** (codename: Mathias) — a privacy-first, AI-powered voice diary app for the DACH market. Users dictate diary entries; the backend transcribes audio and generates structured diary entries with mood tags and follow-up questions via Gemini 2.0 Flash. All data stays in the EU.

- **Firebase project:** `diary-6fa61`
- **Bundle ID:** `com.diary.app`
- **Target platforms:** iOS (min 15.0), Android, Web (full recording support via WebSocket streaming)

## Commands

### Flutter App

```bash
cd flutter
flutter pub get
flutter run                                  # iOS/Android on connected device
flutter run -d chrome                        # Web
flutter analyze
flutter test
flutter test test/path/to/test.dart
flutter build apk
flutter build ios
```

### Backend Services

Each service has its own Python 3.12 venv. Use `/opt/homebrew/bin/python3.12` to create them.

```bash
cd ai-proxy              # or gdpr-export
python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt

LOG_FILE=../log/ai-proxy.log .venv/bin/uvicorn app.main:app --reload --port 8080   # ai-proxy dev server
.venv/bin/uvicorn app.main:app --reload --port 8081                                 # gdpr-export dev server

# Deploy to Cloud Run (always europe-west3)
docker build -t <service>:latest .
gcloud run deploy <service> --image <service>:latest --region europe-west3
```

**Logs:** ai-proxy writes to `log/ai-proxy.log` (controlled by `LOG_FILE` env var).

### Firebase

```bash
# Regenerate firebase_options.dart after Firebase project changes
cd flutter && flutterfire configure --project=diary-6fa61 --platforms=android,ios,web
```

## Architecture

### System Design

```
Flutter App (iOS/Android/Web)
  └─► Firebase Auth (anonymous, user identity)
  └─► ai-proxy (Cloud Run)
  │     POST /transcribe         (native) audio blob → Chirp 3
  │     WS   /transcribe/ws      (web) PCM16 stream → WAV chunks → Chirp 3
  │     POST /entries/normalize  → Vertex AI Gemini 2.0 Flash
  │     POST /entries/generate   → Vertex AI Gemini 2.0 Flash
  │     POST /entries/merge      → Vertex AI Gemini 2.0 Flash
  │     audio bytes processed in RAM, never persisted
  └─► Cloud Firestore (eu-eur3, entries per user)
  └─► Drift (SQLite, local source of truth)

gdpr-export (Cloud Run) ──► Firestore (JSON export / account deletion)
```

### Flutter App (`flutter/lib/`)

Riverpod 3 + GoRouter 17, Material Design 3 (seed `#4A90D9`), offline-first via Drift (SQLite).

#### Routes

| Path | Screen | GoRouter `extra` |
|---|---|---|
| `/` | `RecordingScreen` | `RecordingContext?` (defaults to `FreshRecording`) |
| `/topics` | `TopicsReviewScreen` | `({String date, String duration, List<TopicDto> topics, String transcript})?` |
| `/entry/:date` | `EntryScreen` | — |
| `/history` | `HistoryScreen` | — |

#### Recording Flow

The primary user journey is `/` → `/topics` → `/entry/:date`.

**`RecordingContext`** (`features/recording/recording_context.dart`) is a sealed class passed as GoRouter `extra` to `/`:
- `FreshRecording` — default, new entry
- `ExtendingTopic({topicTitle, followUpHint?})` — returning from Topics to add to a specific topic
- `AddingTopic` — returning from Topics to record a new topic

**Navigation stack rules — critical:**
- `context.push()` for: recording→topics, topics→entry. These stack screens so back works.
- `context.go('/')` for: "Von vorne anfangen", "Ergänzen", "Neues Thema" — these intentionally reset the stack.
- `TopicsReviewScreen` back button: `context.pop()` when topics exist; `context.go('/')` when `_topics.isEmpty` (no orphaned back button on RecordingScreen after full delete).
- Deleting the last topic auto-calls `context.go('/')` — no empty-state limbo.

**`RecordingScreen` continuation state:**
- `_hasExistingEntry` flag: set to `true` when first recording pushes to `/topics`. Survives the user popping back.
- When `_hasExistingEntry && state == idle`: shows `< Themen` nav button (top-left), a "Wird zum Eintrag ergänzt" chip, and adapted subtitle. The button re-pushes `/topics` using stored `_lastDate`/`_lastDuration`.
- When `_hasExistingEntry` is false: no back button (fresh session or after "Von vorne anfangen").

**Recording pipeline** (`_stopRecording` in `recording_screen.dart`):

*Web path:*
1. `RecordingService.start()` → `AudioRecorder.startStream(AudioEncoder.pcm16bits, sampleRate: 16000)` — stream stored in `_webStream`
2. Immediately: `ProxyClient.transcribeWebSocket(_webStream)` starts piping PCM16 chunks over WebSocket to `/transcribe/ws`
3. `RecordingService.stopStream()` → closes the stream, which signals `"done"` to the server
4. Backend assembles PCM16 bytes → wraps in WAV header → chunks into ≤55 s segments → Chirp 3 (auto-detect)
5. WebSocket future resolves with raw transcript string

*Native path:*
1. `RecordingService.stopAndRead()` → M4A file bytes
2. `ProxyClient.transcribe(audio)` → HTTP POST `/transcribe/` → Chirp 3

*Both paths continue:*
3. `ProxyClient.normalize(transcript)` → cleaned text
4. `ProxyClient.generateEntry(normalized)` → `EntryDto` with topics, mood, follow-ups
5. `EntryRepository.saveEntry(...)` → Drift + Firestore sync
6. State reset to idle + `context.push('/topics', extra: (date, duration, topics, transcript))`

#### Data model (`shared/models/entry.dart`)
- `Entry` — one per calendar day; fields: `bodyMarkdown`, `rawTranscripts`, `followUpQuestions`, `mood` (enum), `moodScore` (-1.0…+1.0), `durationSeconds`, `language`, `version`
- `Transcript` — raw audio-to-text result attached to an Entry
- Multiple voice recordings on the same day are merged via Prompt B (not appended as separate entries)

#### Key architectural rules
- Drift (SQLite) is the local source of truth; Firestore syncs in background
- `local_auth` must be guarded with `!kIsWeb` — the package does not compile for web
- `authServiceProvider` warmup is guarded with `if (!kIsWeb)` in `main.dart` — Firebase Auth is not initialised on web
- `ProxyClient` skips the `Authorization` header when `_baseUrl` contains `localhost` — no auth needed for local dev
- `record_web` 1.x `startStream` only supports `AudioEncoder.pcm16bits` — all other encoders throw at runtime

#### Current implementation state

| Screen | State |
|---|---|
| `RecordingScreen` | Complete — real audio pipeline, web + native |
| `TopicsReviewScreen` | Complete — real data from pipeline; topic cards, collapsible transcript, per-topic delete, "Von vorne anfangen", sticky CTA |
| `EntryScreen` | Skeleton ("IN PROGRESS") |
| `HistoryScreen` | Skeleton |
| `settings/` | Folder exists, no route wired yet |

### ai-proxy (`ai-proxy/app/`)

FastAPI service. All routes require `X-Firebase-AppCheck` header (verified by `services/auth.py`). Auth is skipped automatically for `localhost` by the Flutter client.

| Route | Description |
|---|---|
| `POST /transcribe/` | Audio (m4a/aac/wav, max 10 MB) → raw transcript via Chirp 3 |
| `WS /transcribe/ws` | PCM16 stream chunks + `"done"` sentinel → WAV-wrapped chunks → Chirp 3 |
| `POST /entries/normalize` | Raw transcript → cleaned text via Gemini |
| `POST /entries/generate` | Transcript → diary entry JSON (Prompt A) |
| `POST /entries/merge` | Existing entry + new transcript → merged entry JSON (Prompt B) |
| `GET /health` | Liveness check |

**Speech-to-Text:** Chirp 3 (`chirp_3`), location `eu`, endpoint `eu-speech.googleapis.com`. The `_` default recognizer requires `locations/eu` — regional paths (`europe-west3`, `europe-west4`) and `global` are rejected. Synchronous `RecognizeRequest` is capped at 60 s; the WS route chunks PCM16 into ≤55 s WAV segments to stay under this limit.

**Gemini model:** `gemini-2.0-flash-001`, `temperature=0.7`, JSON output mode. The AI persona is named **Mathias** — warm, restrained, writes in first person using the user's own words, adds no invented content.

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
- **Web audio:** `kIsWeb` must gate any `local_auth` usage. The `record` package itself works on web, but only `AudioEncoder.pcm16bits` is supported for `startStream`.
- **`firebase_options.dart`** is gitignored (contains API keys). Regenerate with `flutterfire configure` after cloning.
