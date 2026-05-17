# AI Tagebuch – MVP-Konzept

**Arbeitstitel:** AI Tagebuch (Codename: *Mathias*)
**Version:** 0.1 – Konzept-Entwurf
**Datum:** 17. Mai 2026
**Zielgruppe:** Gen Z & junge Millennials (18–32) im DACH-Raum
**Plattform:** Cross-Platform Mobile (Flutter – iOS + Android aus einer Codebase)
**Backend:** Firebase (Auth, Firestore, Storage) + GCP Cloud Run (Docker) in `europe-west3` (Frankfurt)
**Sprache:** Deutsch (DACH-First)

---

## 1. Vision in einem Satz

> Ein KI-gestütztes Sprach-Tagebuch, das aus einem einzigen Tipp und einem freien Monolog jeden Tag einen vollständigen, durchdachten Eintrag macht – ohne dass der Nutzer schreiben oder die KI ihn ständig unterbrechen muss.

## 2. Positionierung & USP

Der Markt ist gespalten zwischen passiven Archivierungs-Apps (Day One) und überfordernden KI-Coaches (Rosebud, "Drill-Sergeant-Effekt"). **Unser Wedge** sitzt dazwischen:

| Wettbewerber | Schwäche | Unsere Antwort |
|---|---|---|
| **Rosebud** | Permanente Rückfragen während des Schreibens stören den Flow | **Asynchrone Fragen**: Erst diktieren, dann Fragen vorgeschlagen bekommen |
| **Day One** | Reines Archiv, keine KI-Tiefe | KI strukturiert, fasst zusammen und vertieft automatisch |
| **AudioPen** | Glättet Sprache, aber keine psychologische Tiefe | Sinnvolle Folgefragen führen zu reicheren Einträgen |
| **Mindsera** | Teuer (19,99 USD/Monat), analytisch-kühl | Niedrigschwellig, warm, mobile-first auf Deutsch |

**Unser Kern-Versprechen für den MVP:**
*„Sprich 60 Sekunden – bekomme einen Eintrag, den du selbst niemals so geschrieben hättest, und drei Fragen, die ihn perfekt machen."*

## 3. Zielgruppen-Persona

**Lena, 26, Berlin, Marketing Managerin**
- Hört Podcasts, schickt Voice Messages, hat Calm/Headspace probiert
- Will reflektieren, aber: „Schreiben kostet zu viel Energie nach einem 10-Stunden-Tag"
- Datenschutz-bewusst, würde DSGVO-konformer DACH-App eher vertrauen als US-Cloud
- Zahlt 5–7 €/Monat für eine App, die ihr wirklich hilft – kein 15 €-Abo

## 4. MVP-Scope: Was ist drin – was nicht

### ✅ Im MVP enthalten

1. **One-Tap Aufnahme** – ein zentraler Button „Tagebucheintrag erstellen"
2. **Speech-to-Text** – Transkription über Whisper API
3. **Eintrags-Generierung** – LLM formt aus dem Transkript einen kohärenten Tagebucheintrag in der Ich-Form
4. **Folgefragen** – LLM schlägt 2–3 sinnvolle Vertiefungsfragen vor
5. **Ergänzungs-Flow** – Button „Eintrag ergänzen" → erneut diktieren → KI integriert die Antwort organisch in den bestehenden Eintrag
6. **Tages-Stream** – pro Tag genau ein Eintrag (Mehrfach-Diktate werden zusammengeführt)
7. **Verlauf** – Chronologische Liste aller Tage mit Vorschau
8. **Stimmungs-Tag** – KI extrahiert eine Stimmung pro Eintrag (😊 😌 😐 😤 😟 🌀 → happy / calm / neutral / tense / sad / mixed)
9. **Lokale Speicherung + Cloud-Backup** – verschlüsselt, GDPR-konform (Hetzner/Frankfurt)
10. **Onboarding** – 3 Screens, dann direkt zum Aufnahme-Button

### ❌ Bewusst NICHT im MVP

- Wöchentliche/monatliche Retrospektiven *(Phase 2)*
- Apple-Health- / Calendar-Integration *(Phase 2)*
- Wissensgraph & Entitäten-Extraktion *(Phase 2)*
- Lokale LLM-Inferenz auf dem Gerät *(Phase 3)*
- Trusted Execution Environments *(Phase 3)*
- Soziale Features, Sharing, Export-PDFs
- Premium-Tier *(MVP läuft als Closed Beta kostenlos)*

## 5. User Journey – Ein Tag mit der App

```
21:30 Uhr — Lena auf dem Sofa
   │
   ▼
[App öffnen] ──► Startscreen: großer runder Button "Tagebucheintrag erstellen"
   │
   ▼
[Tap] ──► Aufnahme läuft, dezente Waveform-Animation, Stopp-Button
   │
   ▼
Lena spricht ~90 Sekunden frei
   │
   ▼
[Stopp] ──► Loading 3-5 Sek ("Mathias formuliert deinen Eintrag…")
   │
   ▼
Eintrag wird angezeigt: 1-2 Absätze, ich-Form, ihre Stimme, geglättet
   │
   ▼
Darunter: "Mathias hat ein paar Fragen für dich:"
   ●  „Was hat dich an dem Gespräch mit Tim am meisten beschäftigt?"
   ●  „Du hast zweimal 'eigentlich' gesagt – was hättest du wirklich gewollt?"
   ●  „Welche Entscheidung steht morgen an?"
   │
   ├── [Eintrag speichern] ──► fertig
   │
   └── [Eintrag ergänzen] ──► neue Aufnahme, KI integriert nahtlos
```

## 6. Screens (Wireframe-Übersicht)

| # | Screen | Kernelemente |
|---|---|---|
| 1 | **Onboarding (3 Slides)** | Hero-Versprechen, Mikrofon-Permission, Beispiel-Eintrag |
| 2 | **Home / Heute** | Datum, großer Button „Tagebucheintrag erstellen", darunter Verlauf-Teaser |
| 3 | **Aufnahme** | Vollbild-Waveform, Timer, Stopp-Button, „Verwerfen" |
| 4 | **Eintrag-Ansicht** | Eintragstext, Stimmungs-Tag, Folgefragen, „Ergänzen" / „Speichern" |
| 5 | **Verlauf** | Liste vergangener Tage, je Karte: Datum, Stimmung, 1-Zeilen-Preview |
| 6 | **Detail-Ansicht** | Vollständiger Eintrag mit Bearbeiten-Option |
| 7 | **Settings** | Account, Sprache, Datenexport (GDPR), Konto löschen |

## 7. Datenmodell

```typescript
type Entry = {
  id: string;                    // UUID
  userId: string;
  date: string;                  // YYYY-MM-DD (ein Eintrag pro Tag)
  createdAt: ISODateString;
  updatedAt: ISODateString;

  // Inhaltsdaten
  bodyMarkdown: string;          // Der finale, KI-generierte Tagebucheintrag
  rawTranscripts: Transcript[];  // Alle bisherigen Diktate dieses Tages
  followUpQuestions: string[];   // 2-3 offene Fragen
  mood: Mood;                    // happy | calm | neutral | tense | sad | mixed
  moodScore: number;             // -1.0 bis +1.0

  // Meta
  durationSeconds: number;       // gesamte Diktat-Zeit
  language: 'de' | 'en';
  version: number;               // wie oft wurde der Eintrag durch Ergänzungen überarbeitet
};

type Transcript = {
  id: string;
  text: string;                  // Roh-Transkript (Audio wird nie persistiert)
  createdAt: ISODateString;
};
```

## 8. Tech-Stack

Verbindlich gesetzt: **Flutter** im Frontend, **Firebase** als Managed-Backend-Plattform, **GCP Cloud Run + Docker** für eigene Server-Logik (z. B. KI-Proxy). Alle Cloud-Ressourcen werden in `europe-west3` (Frankfurt) bzw. `eur3` (EU-Multiregion) gehostet — DSGVO-konform und passend zum DACH-Marketing-Pitch.

### Frontend (Flutter)

| Bereich | Wahl | Zweck |
|---|---|---|
| **Framework** | Flutter (stable channel) + Dart 3 | Eine Codebase für iOS + Android, native Performance |
| **State Management** | Riverpod 2 | Compile-safe, testbar, gut für asynchrone Flows (Audio + KI) |
| **Audio-Aufnahme** | `record` + `audio_session` | Saubere Mikrofon-Berechtigungen, kompatibel mit iOS/Android, m4a/AAC-Output |
| **Lokale DB** | Drift (SQLite) | Reaktiv, Offline-First, typsicher; Cache vor Firestore-Sync |
| **Auth-Client** | `firebase_auth` | Magic Link, Apple Sign-In, Google Sign-In |
| **Datenbank-Client** | `cloud_firestore` | Offline-Cache out-of-the-box |
| **Storage-Client** | `firebase_storage` | Für Audio-Files (vor Auto-Delete) |
| **HTTP zur Cloud Run** | `dio` + Firebase App Check Token | Schutz vor Missbrauch des KI-Proxies |
| **Biometric Lock** | `local_auth` | FaceID / TouchID / Android BiometricPrompt |

### Backend (Firebase)

| Bereich | Wahl | Zweck |
|---|---|---|
| **Auth** | Firebase Authentication | E-Mail Magic Link + Apple/Google SSO; Standort EU |
| **Datenbank** | Cloud Firestore (Region `eur3`) | NoSQL, Offline-Sync, Security Rules pro Nutzer |
| **Object Storage** | Cloud Storage for Firebase (`europe-west3`) | GDPR-Export ZIP-Dateien (temporär); kein Audio-Storage |
| **Push Notifications** | Firebase Cloud Messaging | Optionale tägliche Erinnerung „Zeit für deinen Eintrag" |
| **App-Schutz** | Firebase App Check (App Attest / Play Integrity) | Nur echte App-Installationen dürfen Cloud Run aufrufen |
| **Crash Reports** | Firebase Crashlytics | Native Integration, kostenlos |
| **Analytics** | Firebase Analytics (mit Consent) | Privacy-first konfiguriert; optional alternativ PostHog self-hosted |

### Eigene Server-Komponenten (GCP Cloud Run + Docker)

Sämtliche Logik, die nicht direkt von Firebase abgedeckt wird, läuft als **stateless Docker-Container auf Cloud Run** in `europe-west3`. Vorteile: Skaliert auf Null herunter (kostengünstig), automatische TLS, Deployment via `gcloud run deploy`, gleiches Container-Image kann lokal laufen.

| Service | Stack | Zweck |
|---|---|---|
| **`ai-proxy`** | Python 3.12 + FastAPI, Docker | Empfängt Audio per HTTP-Multipart, verarbeitet es **ausschließlich im RAM** (Cloud Speech-to-Text → Gemini), hält API-Keys serverseitig (Secret Manager), erzwingt App-Check-Token, Rate Limiting, Logging |
| **`gdpr-export`** | Python 3.12 + FastAPI, Docker | Auf Nutzer-Anfrage: Firestore-Daten als JSON.zip exportieren oder Account + alle Firestore-Dokumente löschen |

**Build & Deploy:**
- **CI/CD:** GitHub Actions → Cloud Build → Artifact Registry → Cloud Run
- **Secrets:** GCP Secret Manager (Vertex AI Service-Account-Keys) — niemals im App-Bundle
- **Observability:** Cloud Logging + Cloud Monitoring, Alerts auf Latenz & Fehlerquote

### KI-Provider

| Komponente | Wahl | Begründung |
|---|---|---|
| **STT** | Google Cloud Speech-to-Text v2 (Chirp) | ~0,006 USD/Min, exzellente Deutsch-Qualität inkl. Dialekt, nativ in GCP, DSGVO-konform in `europe-west3` |
| **LLM (primär)** | Gemini 2.0 Flash (Vertex AI) | Günstig, sehr schnell, hervorragende Deutsch-Qualität, strukturierter JSON-Output via Function Calling |
| **LLM (Fallback)** | Gemini 1.5 Pro (Vertex AI) | Robuster Fallback bei Flash-Kapazitätsengpässen, gleiche JSON-Struktur via Vertex AI Function Calling |

> **Hinweis zur DSGVO:** Alle KI-Komponenten laufen über **Vertex AI** in der Region `europe-west3` (Frankfurt). Google bietet für Vertex AI Data-Processing-Addenda nach DSGVO Art. 28 an; Daten verlassen die EU nicht. Kein Drittanbieter-Vertrag nötig – der gesamte KI-Stack bleibt innerhalb des GCP-Projekts.

## 9. KI-Architektur & Beispiel-Prompts

### Pipeline

```
Flutter (Record-Button)
   │  multipart/form-data  (audio bytes, max 10 MB)
   ▼
[ai-proxy – Cloud Run RAM]
   │
   ├─► Cloud Speech-to-Text v2 (Chirp, de-DE) ──► Roh-Transkript (string)
   │                                                         │
   │   Audio-Bytes werden nach Antwort verworfen ◄───────────┘
   │   (niemals in Storage persistiert)
   │
   ▼
[Gemini 2.0 Flash via Vertex AI – Prompt A: Entry-Generation]
   │
   ▼
{ bodyMarkdown, mood, moodScore, followUpQuestions[] }
   │
   ▼
In Firestore + lokalem Drift-Cache speichern
   │
   └── Bei "Ergänzen": neues Audio → selber RAM-Flow → Prompt B: Entry-Merge
```

### Prompt A – Eintrags-Erstellung (erstes Diktat)

```
System:
Du bist Mathias, ein zurückhaltender, warmherziger Tagebuch-Assistent.
Aus dem rohen Sprachtranskript des Nutzers formst du einen
Tagebucheintrag in der Ich-Form, in seiner Sprache, mit seiner
Wortwahl. Du fügst KEINE Informationen hinzu, die nicht im
Transkript stehen. Du glättest Füllwörter, ordnest Gedanken
chronologisch und brichst lange Sätze auf.

Gib AUSSCHLIESSLICH valides JSON zurück mit dieser Struktur:
{
  "bodyMarkdown": "1-3 Absätze, ich-Form, max. 250 Wörter",
  "mood": "happy" | "calm" | "neutral" | "tense" | "sad" | "mixed",
  "moodScore": Zahl zwischen -1.0 und +1.0,
  "followUpQuestions": [
    "Genau eine offene Frage, keine Ja/Nein-Frage",
    "Bezieht sich auf etwas Konkretes aus dem Eintrag",
    "Dritte Frage geht in die Tiefe, nicht in die Breite"
  ]
}

Regeln für die Fragen:
- Keine Ratschläge, keine Therapie-Phrasen
- Keine Frage darf mit "Wie fühlst du dich?" beginnen
- Greife konkrete Wörter aus dem Eintrag auf
- Maximal 15 Wörter pro Frage

User:
[Roh-Transkript hier]
```

### Prompt B – Eintrags-Ergänzung (Merge)

```
System:
Du bist Mathias. Der Nutzer hat heute bereits einen Eintrag verfasst
und gerade weitere Gedanken diktiert – meist als Antwort auf eine
deiner Folgefragen. Integriere die neuen Inhalte ORGANISCH in den
bestehenden Eintrag: Dopplungen entfernen, chronologisch ordnen,
gleicher Ton. Generiere danach 2-3 NEUE Folgefragen, die noch nicht
beantwortet wurden.

Gib JSON in der gleichen Struktur wie zuvor zurück.

User:
BESTEHENDER EINTRAG:
[bodyMarkdown bisher]

NEUE GEDANKEN (Transkript):
[neues Transkript]

BISHERIGE FOLGEFRAGEN (nicht wiederholen):
[bisherige followUpQuestions]
```

### Kostenrechnung pro Nutzer / Monat

Annahme: 90 Sek Diktat × 1,4 Sessions/Tag = ~63 Min Audio/Monat
- Cloud Speech-to-Text (Chirp): 63 × 0,006 USD = **0,38 USD**
- Gemini 2.0 Flash (Vertex AI): ca. **0,02 USD**
- **Total ~0,40 USD/Nutzer/Monat** – komfortabel im Rahmen der Marktanalyse (0,93 USD)

## 10. Privacy für den MVP

Der MVP geht **nicht** schon mit lokaler LLM-Inferenz live (das ist Phase 3). Aber wir setzen die Grundlagen so, dass spätere Migration trivial ist:

| Maßnahme | MVP | Phase 2 | Phase 3 |
|---|---|---|---|
| TLS 1.3 in transit | ✅ | ✅ | ✅ |
| AES-256 at rest (Firestore / Cloud Storage) | ✅ | ✅ | ✅ |
| Hosting EU-Frankfurt | ✅ | ✅ | ✅ |
| Audio nur im RAM verarbeitet, niemals persistiert | ✅ | ✅ | ✅ |
| GDPR Datenexport (JSON) & Account-Löschung | ✅ | ✅ | ✅ |
| Biometrischer App-Lock | ✅ | ✅ | ✅ |
| Pseudonymisierung an OpenAI/Anthropic (Zero Data Retention Vertrag) | ✅ | ✅ | ✅ |
| E2EE Sync zwischen Geräten | – | ✅ | ✅ |
| Lokale LLM-Inferenz (Gemini Nano on-device via ML Kit) | – | – | ✅ |
| TEE (Apple PCC) | – | – | ✅ |

**Wichtig für den DACH-Marketing-Pitch:**
„Deutsche App, gehostet in Frankfurt, DSGVO by Design, deine Audio-Aufnahmen werden nach der Transkription sofort gelöscht."

## 11. Roadmap

**Phase 1 – MVP (10–12 Wochen)**
Geschlossene Beta mit 50–100 Nutzern. Ziel: Validierung des Kern-Flows und der Folgefragen-Qualität.

**Phase 2 – Insight-Maschine (3 Monate nach MVP)**
- Wöchentliche Retrospektive (KI-Zusammenfassung)
- Stimmungs-Verlaufs-Diagramm
- Strukturierte Entitäten-Extraktion (Personen, Themen, Habits)
- Premium-Tier Launch (5,99 €/Monat)
- App-Store-Release

**Phase 3 – Privacy Excellence (6 Monate nach MVP)**
- On-Device-LLM via Gemini Nano (ML Kit) für die Eintragsgenerierung
- Apple Private Cloud Compute Integration (iOS) / Android AICore (Android)
- E2EE-Sync
- Apple Health / Google Fit Integration

## 12. Erfolgskriterien des MVP

- ≥ 40 % der Beta-Tester nutzen die App ≥ 4 Tage pro Woche
- Durchschnittliche Sitzungsdauer: 60–120 Sekunden Diktat
- ≥ 25 % nutzen den „Eintrag ergänzen"-Flow regelmäßig (Indikator: Folgefragen funktionieren)
- NPS ≥ 40
- Qualitatives Feedback: „Klingt wirklich wie meine Stimme/Gedanken"

## 13. Offene Entscheidungen

Folgende Punkte müssen wir noch klären, bevor die Implementierung beginnt:

1. **„Ein Eintrag pro Tag" vs. mehrere:** Was ist die Definition eines „Tages" – Kalendertag oder 04:00-bis-04:00-Fenster (für Nachteulen)?
2. **Onboarding-Anmeldung:** Magic Link per E-Mail, oder erst Beta-Code, oder Apple/Google Sign-In?
3. **Beta-Distribution:** TestFlight + Google Play Internal Testing, oder Expo-Go für maximale Geschwindigkeit?
4. **Name:** Bleibt es bei „Mathias" als KI-Persönlichkeit oder soll der Nutzer den Namen wählen können?
5. **Pre-Build-Validierung:** Wollen wir vorher noch eine Landingpage + Warteliste bauen, um die Nachfrage zu testen?

---

**Nächster Schritt:** Diese Punkte gemeinsam durchgehen, dann starte ich mit dem Flutter-Projekt-Setup und einem ersten klickbaren Prototyp.
