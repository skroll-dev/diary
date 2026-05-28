# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication Style

- **When writing or editing code:** Communicate like **Captain Jean-Luc Picard** — decisive, precise, authoritative. Short commands. "Make it so." No hedging. Confidence in every line.
- **When giving advice, recommendations, or discussing trade-offs:** Communicate like **Counselor Deanna Troi** — empathetic, thoughtful, attuned to the bigger picture. Help the user feel the implications of a decision, not just the technical facts.

## Project Overview

**AI Tagebuch** (codename: Mathias) — a privacy-first, AI-powered voice diary app for the DACH market. Users dictate diary entries; the backend transcribes audio and generates structured diary entries with mood tags and follow-up questions via Gemini 2.0 Flash. All data stays in the EU.

- **Firebase project:** `diary-6fa61`
- **Bundle ID:** `com.diary.app`
- **Target platforms:** iOS (min 15.0), Android, Web (web = layout/review only; audio recording is blocked on web with a user-facing hint)

## Commands

### Flutter App

```bash
cd flutter
flutter pub get
flutter run                                  # iOS/Android on connected device
flutter run -d chrome                        # Web (layout verification)
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

.venv/bin/uvicorn app.main:app --reload --port 8080   # ai-proxy dev server
.venv/bin/uvicorn app.main:app --reload --port 8081   # gdpr-export dev server

# Deploy to Cloud Run (always europe-west3)
docker build -t <service>:latest .
gcloud run deploy <service> --image <service>:latest --region europe-west3
```

### Firebase

```bash
# Regenerate firebase_options.dart after Firebase project changes
cd flutter && flutterfire configure --project=diary-6fa61 --platforms=android,ios,web
```

## Architecture

### System Design

```
Flutter App (iOS/Android/Web)
  └─► Firebase Auth (user identity)
  └─► ai-proxy (Cloud Run) ──► Cloud Speech-to-Text v2 (Chirp, de-DE)
  │     audio bytes in RAM  └─► Vertex AI Gemini 2.0 Flash (entry generation)
  │     never persisted
  └─► Cloud Firestore (eu-eur3, entries per user)

gdpr-export (Cloud Run) ──► Firestore (JSON export / account deletion)
```

### Flutter App (`flutter/lib/`)

Riverpod 3 + GoRouter 17, Material Design 3 (seed `#4A90D9`), offline-first via Drift (SQLite).

#### Routes

| Path | Screen | GoRouter `extra` |
|---|---|---|
| `/` | `RecordingScreen` | `RecordingContext?` (defaults to `FreshRecording`) |
| `/topics` | `TopicsReviewScreen` | `({String date, String duration})?` |
| `/entry/:date` | `EntryScreen` | — |
| `/history` | `HistoryScreen` | — |

#### Recording Flow

The primary user journey is `/` → `/topics` → `/entry/:date`.

**`RecordingContext`** (`features/recording/recording_context.dart`) is a sealed class passed as GoRouter `extra` to `/`:
- `FreshRecording` — default, new entry
- `ExtendingTopic({topicTitle, followUpHint?})` — returning from Topics to add to a specific topic; subtitle on RecordingScreen shows the topic-specific follow-up question
- `AddingTopic` — returning from Topics to record a new topic

When recording stops, `RecordingScreen` captures `_dateLabel` and `_timerLabel` **before** the async processing delay, then navigates: `context.go('/topics', extra: (date: date, duration: duration))`. The router unwraps this record and passes it to `TopicsReviewScreen` as constructor params.

**`TopicsReviewScreen`** holds a mutable `_topics` list (copy of sample data). Supports per-topic deletion (with confirmation dialog), global "Von vorne anfangen" (wipes all → navigates to `/` with `FreshRecording`), and "Ergänzen" (→ `/` with `ExtendingTopic`).

#### Data model (`shared/models/entry.dart`)
- `Entry` — one per calendar day; fields: `bodyMarkdown`, `rawTranscripts`, `followUpQuestions`, `mood` (enum), `moodScore` (-1.0…+1.0), `durationSeconds`, `language`, `version`
- `Transcript` — raw audio-to-text result attached to an Entry
- Multiple voice recordings on the same day are merged via Prompt B (not appended as separate entries)

#### Key architectural rules
- Drift (SQLite) is the local source of truth; Firestore syncs in background
- Audio → Firebase Storage → ai-proxy transcription → auto-delete from Storage
- `kIsWeb` guards all audio recording paths; web shows an "App only" hint instead

#### Current implementation state

| Screen | State |
|---|---|
| `RecordingScreen` | UI complete — animated waveform, 3 states (idle/recording/processing), context-aware subtitles. No real audio yet. |
| `TopicsReviewScreen` | UI complete — topic cards, per-topic delete, "Von vorne anfangen", sticky CTA. Sample data only. |
| `EntryScreen` | Skeleton ("IN PROGRESS") |
| `HistoryScreen` | Skeleton |
| `settings/` | Folder exists, no route wired yet |

### ai-proxy (`ai-proxy/app/`)

FastAPI service. All routes require `X-Firebase-AppCheck` header (verified by `services/auth.py`).

| Route | Description |
|---|---|
| `POST /transcribe` | Audio file (m4a/aac/wav, max 10 MB) → raw transcript via Cloud Speech-to-Text Chirp |
| `POST /entries/generate` | Transcript → diary entry JSON (Prompt A) |
| `POST /entries/merge` | Existing entry + new transcript → merged entry JSON (Prompt B) |
| `GET /health` | Liveness check |

Gemini model: `gemini-2.0-flash-001`, `temperature=0.7`, JSON output mode. The AI persona is named **Mathias** — warm, restrained, writes in first person using the user's own words, adds no invented content.

### gdpr-export (`gdpr-export/app/`)

FastAPI service for DSGVO compliance: exports all user Firestore data as a JSON ZIP, or deletes the account and all associated Firestore documents.

### Agent Skills

31 Open Agent Skills in `.agents/skills/`. **Before writing code for a relevant domain, read the matching `SKILL.md` first.**

Key skills:
- `firebase-firestore` — mandatory for any Firestore work (security rules, queries, indexes)
- `flutter-apply-architecture-best-practices` — Riverpod + layered architecture patterns
- `cloud-run-basics` — deploying/updating Cloud Run services
- `gemini-api` — Vertex AI / Gemini SDK patterns
- `ui-ux-pro-max` — design system, color/typography, UX patterns (invoke via `/ui-ux-pro-max` skill)

See `AGENTS.md` for the full skill matrix and workflow rule.

## Key Constraints

- **GDPR / DSGVO:** All GCP resources must stay in `europe-west3` or `eu-eur3`. Audio files must be deleted after transcription (retention via `AUDIO_RETENTION_HOURS`).
- **Firebase App Check** is required on all ai-proxy routes — the Flutter client must attach an App Check token to every request.
- **Web audio:** `kIsWeb` must gate any `record` / `local_auth` usage. Never import these packages unconditionally — they will fail to compile for web.
- **`firebase_options.dart`** is gitignored (contains API keys). Regenerate with `flutterfire configure` after cloning.
