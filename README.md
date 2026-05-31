# AI Tagebuch — Codename *Mathias*

> *"Sprich 60 Sekunden – bekomme einen Eintrag, den du selbst niemals so geschrieben hättest."*

A privacy-first, AI-powered voice diary for the DACH market. Users dictate freely; Mathias — the AI persona — shapes their words into a coherent diary entry, preserves their voice, and proposes follow-up questions that go deeper, not wider.

**Status:** UI prototype in progress — recording and topics screens complete, entry/history screens pending  
**Platforms:** iOS (15.0+) · Android · Web  
**All data stays in Frankfurt, EU.**

---

## The Idea

Most journaling apps are either passive archives (Day One) or exhausting AI coaches that interrupt your flow (Rosebud). *AI Tagebuch* sits between them:

1. **One tap** — start recording
2. **Speak freely** — 30–120 seconds, no structure needed
3. **Mathias writes** — a first-person diary entry in your words, your tone
4. **Review topics** — Mathias identifies the themes it heard; deepen any of them or add a new one
5. **Optional: dictate again** — Mathias merges the new thoughts organically into the existing entry

One entry per calendar day. Multiple recordings merge, not stack.

---

## Screen Flow

```
RecordingScreen (/)
  │  tap record → speak → tap stop
  ▼
TopicsReviewScreen (/topics)
  │  "Ergänzen" on a topic → back to RecordingScreen with topic context
  │  "Neues Thema" → back to RecordingScreen in add-topic mode
  │  "Eintrag erstellen" →
  ▼
EntryScreen (/entry/:date)          ← skeleton, pending
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Flutter App (iOS / Android / Web)       │
│                                                          │
│  Firebase Auth ──► identity & session                    │
│  Drift (SQLite) ──► offline-first local cache            │
│  Cloud Firestore ──► cloud sync (eu-eur3)                │
└──────────────────────────┬──────────────────────────────┘
                           │  HTTPS + Firebase App Check
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  ai-proxy  (Cloud Run)                   │
│                                                          │
│  Audio bytes ──► Cloud Speech-to-Text v2 (Chirp, de-DE) │
│             ──► Gemini 2.0 Flash (Vertex AI)             │
│                                                          │
│  Audio is processed in RAM only — never persisted.       │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│               gdpr-export  (Cloud Run)                   │
│  On user request: export Firestore data as JSON ZIP      │
│  or delete account + all data (DSGVO Art. 17)            │
└─────────────────────────────────────────────────────────┘
```

---

## Modules

### `flutter/` — Mobile & Web App

Cross-platform client built with Flutter (Dart). Offline-first: Drift (SQLite) is the local source of truth; Firestore syncs in the background.

| Area | Choice |
|---|---|
| State management | Riverpod 3 |
| Routing | GoRouter 17 |
| Local DB | Drift (SQLite) |
| Audio recording | `record` package (iOS/Android/Web) |
| UI | Material Design 3, seed `#4A90D9` |
| Auth | Firebase Auth |
| App protection | Firebase App Check (App Attest / Play Integrity) |
| Biometric lock | `local_auth` (FaceID / TouchID / BiometricPrompt) |

> Web is fully supported. Audio recording uses PCM16 streaming over WebSocket on web.

---

### `ai-proxy/` — AI Orchestration Service

Stateless FastAPI service on Cloud Run. Receives audio, transcribes it, generates the diary entry — all in RAM. No audio ever touches persistent storage.

| Route | Description |
|---|---|
| `POST /transcribe/` | Audio (m4a/aac/wav, max 10 MB) → raw transcript |
| `WS /transcribe/ws` | PCM16 stream (web) → raw transcript |
| `POST /entries/normalize` | Raw transcript → cleaned text |
| `POST /entries/generate` | Transcript → diary entry JSON (Prompt A) |
| `POST /entries/merge` | Existing entry + new transcript → merged entry (Prompt B) |
| `GET /health` | Liveness check |

All routes require a valid Firebase Auth ID token (`Authorization: Bearer <token>`).

**AI model:** Gemini 2.5 Flash via Vertex AI (`europe-west3`), JSON output mode, temperature 0.7.

#### Recording Pipeline — Fresh Entry

```
Flutter                     ai-proxy                        GCP
─────────────────────────────────────────────────────────────────────
┌─────────────┐
│  mic audio  │
└──────┬──────┘
       │  Web    → PCM16 stream   →  WS  /transcribe/ws  ─┐
       │  Native → M4A bytes      →  POST /transcribe/   ─┴─► Chirp 3
       │                                                        (eu, de-DE)
       │                    raw transcript
       │                    (unpolished STT output)
       │                          │
       │                          ▼
       │                POST /entries/normalize  ──────────► Gemini
       │
       │                    cleaned text
       │                    (Perfekt, no fillers, natural sentences)
       │                          │
       │                          ▼
       │                POST /entries/generate   ──────────► Gemini
       │
       │                    EntryDto
       │                    ├─ body_markdown        first-person prose
       │                    ├─ mood + mood_score     enum · –1.0 … +1.0
       │                    ├─ topics[]              title · summary · follow_up_hint
       │                    └─ follow_up_questions[]
       │                          │
       └──────────────────────────┤
                                  ▼
                       Drift (SQLite, local)
                       Firestore (eu-eur3, cloud sync)
```

#### Recording Pipeline — Extend Existing Entry

```
(transcribe + normalize identical to above)

                    new cleaned text
                    + existing entry body_markdown
                          │
                          ▼
                POST /entries/merge     ──────────────────► Gemini
                    (merges, deduplicates, re-sequences)
                          │
                    updated EntryDto  (same structure)
                          │
                          ▼
               Drift + Firestore (updated in place)
```

---

### `gdpr-export/` — DSGVO Compliance Service

FastAPI service on Cloud Run. Triggered by the user from the Settings screen.

- **Export:** packages all Firestore entries as a JSON ZIP
- **Delete:** removes the Firebase Auth account and all associated Firestore documents

---

## Tech Stack at a Glance

| Layer | Technology |
|---|---|
| Mobile / Web | Flutter (Dart 3) |
| State | Riverpod 3 |
| Backend services | Python 3.12, FastAPI, Docker |
| Speech-to-Text | Google Cloud Speech-to-Text v2 (Chirp) |
| LLM | Gemini 2.0 Flash — Vertex AI (`europe-west3`) |
| Database | Cloud Firestore (`eu-eur3`) + Drift (SQLite, local) |
| Auth | Firebase Authentication |
| App security | Firebase App Check |
| Hosting | Cloud Run (`europe-west3`) |
| Crash reporting | Firebase Crashlytics |
| Analytics | Firebase Analytics |

---

## Privacy & GDPR

- **Audio:** processed in Cloud Run RAM only — never written to disk or object storage
- **All GCP resources:** `europe-west3` (Frankfurt) or `eu-eur3` — data never leaves the EU
- **Vertex AI:** covered by Google's DSGVO Art. 28 Data Processing Addendum
- **User rights:** full data export and account deletion via `gdpr-export` service
- **App lock:** biometric authentication (FaceID / TouchID / Android Biometric)

---

## Repository Layout

```
diary/
├── flutter/          # iOS, Android & Web app
├── ai-proxy/         # Audio transcription + AI entry generation
├── gdpr-export/      # DSGVO data export & account deletion
├── doc/              # MVP concept, market research, investor overview
└── diary.code-workspace  # VSCode multi-root workspace (open this)
```

---

## Getting Started

See [`CLAUDE.md`](CLAUDE.md) for full setup commands, architecture details, and development constraints.

Open the repo in VSCode via `diary.code-workspace` for multi-root support with per-service Python interpreters and Flutter LSP.
