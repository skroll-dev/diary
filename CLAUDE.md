# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Tagebuch** (codename: Mathias) — a privacy-first, AI-powered voice diary app for the DACH market. Users dictate diary entries; the backend transcribes audio and generates structured diary entries with mood tags and follow-up questions via Gemini. All data stays in the EU.

## Commands

### Flutter App

```bash
cd flutter
flutter pub get          # Install dependencies
flutter run              # Run on connected device/emulator
flutter analyze          # Static analysis (dart analyze under the hood)
flutter test             # Run all tests
flutter test test/path/to/test.dart  # Run a single test file
flutter build apk        # Android release build
flutter build ios        # iOS release build
```

### Backend Services (ai-proxy / gdpr-export / cron-cleanup)

```bash
cd ai-proxy              # or gdpr-export / cron-cleanup
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8080   # Dev server (ai-proxy / gdpr-export)
python -m app.main                          # One-shot job (cron-cleanup)

# Deploy to Cloud Run (europe-west3)
docker build -t <service>:latest .
gcloud run deploy <service> --image <service>:latest --region europe-west3
```

## Architecture

### System Design

```
Flutter App (iOS/Android)
  └─► Firebase Auth (user identity)
  └─► ai-proxy (Cloud Run) ──► Cloud Speech-to-Text v2 (Chirp, German)
  │                         └─► Vertex AI Gemini 2.0 Flash (entry generation)
  └─► Cloud Firestore (eu-eur3, entries per user)
  └─► Firebase Storage (europe-west3, audio files — auto-deleted)

gdpr-export (Cloud Run)   ──► Firestore + Storage (ZIP export / account deletion)
cron-cleanup (Cloud Run Job, daily) ──► Storage (delete audio > retention threshold)
```

### Flutter App (`flutter/lib/`)

Clean layered architecture with **Riverpod** for state management:

- `core/router/app_router.dart` — GoRouter with 3 routes: `/` (recording), `/entry/:date`, `/history`
- `core/theme/app_theme.dart` — Material Design 3, seed color `#4A90D9`, light + dark
- `features/<name>/presentation/` — one screen per feature (recording, entry, history, settings)
- `shared/models/entry.dart` — canonical data models: `Entry`, `Transcript`, `Mood` enum
- `shared/services/` — shared service classes (auth, Dio HTTP client, Drift DB)

Key architectural rules:
- **One entry per calendar day** — multiple voice recordings merge into a single entry via Prompt B
- **Offline-first:** Drift (SQLite) is the local source of truth; Firestore syncs in background
- Audio is uploaded to Firebase Storage, transcribed via ai-proxy, then auto-deleted

### AI Proxy Service (`ai-proxy/app/`)

FastAPI service; all AI logic lives in `services/`:

- `services/speech.py` — Cloud Speech-to-Text v2 Chirp, German (`de-DE`), supports m4a/wav/AAC, 10 MB limit
- `services/gemini.py` — Two prompts on Gemini 2.0 Flash (temp 0.7, JSON output):
  - **Prompt A** (`generate_entry`) — transcript → diary entry with `mood`, `summary`, `follow_up_questions`
  - **Prompt B** (`merge_entry`) — existing entry + new transcript → organically merged entry
- `services/auth.py` — Firebase App Check token verification (middleware on all routes)

Routes: `POST /transcribe`, `POST /entries/generate`, `POST /entries/merge`, `GET /health`

### Agent Skills

31 Open Agent Skills are installed in `.agents/skills/`. **Before writing code for a relevant domain, read the matching `SKILL.md` first** — skills contain verified patterns, anti-patterns, and exit criteria.

See `AGENTS.md` for the full skill matrix and the mandatory workflow rule (identify skill → read SKILL.md → write code).

Key skills to reach for:
- `firebase-firestore` — mandatory for any Firestore work (security rules, queries, indexes)
- `flutter-apply-architecture-best-practices` — Riverpod + layered architecture patterns
- `cloud-run-basics` — deploying/updating Cloud Run services
- `gemini-api` — Vertex AI / Gemini SDK patterns

## Key Constraints

- **GDPR / DSGVO:** All GCP resources must stay in `europe-west3` or `eu-eur3`. Audio files must be deleted after transcription (retention configured via `AUDIO_RETENTION_HOURS`).
- **Firebase App Check** is required on all ai-proxy routes — the Flutter client must attach an App Check token to every request.
- **No web MVP** — Flutter target platforms are iOS and Android only.
