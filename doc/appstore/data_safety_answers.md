# Google Play Data Safety — Mein KI-Tagebuch

Ausgefüllte Antworten für den Datensicherheitsabschnitt im Google Play Store.
Grundlage: App-Architektur laut CLAUDE.md (Stand 2026-07-12).

---

## Abschnitt 1: Allgemeine Datenerhebung

| Question ID | Antwort | Begründung |
|---|---|---|
| PSL_DATA_COLLECTION_COLLECTS_PERSONAL_DATA | **true** | Firebase UID, optional E-Mail (Google OAuth), Tagebuchtext |
| PSL_DATA_COLLECTION_ENCRYPTED_IN_TRANSIT | **true** | HTTPS zu Cloud Run + Firebase (TLS) |

---

## Abschnitt 2: Kontoerstellung

| Response ID | Ausgewählt | Begründung |
|---|---|---|
| PSL_ACM_USER_ID_PASSWORD | — | Nicht unterstützt |
| PSL_ACM_USER_ID_OTHER_AUTH | **true** | Anonyme Anmeldung via Firebase Anonymous Auth |
| PSL_ACM_USER_ID_PASSWORD_OTHER_AUTH | — | Nicht unterstützt |
| PSL_ACM_OAUTH | **true** | Google Sign-In (OAuth 2.0) |
| PSL_ACM_OTHER | — | Nicht unterstützt |
| PSL_ACM_NONE | — | Konto wird erstellt (anonym oder Google) |

**PSL_ACM_SPECIFY:** "Nutzer können sich anonym (ohne Registrierung) oder mit ihrem Google-Konto anmelden."

---

## Abschnitt 3: Kontolöschung

| Question ID | Response ID | Antwort |
|---|---|---|
| PSL_ACCOUNT_DELETION_URL | — | `https://github.com/skroll-dev/diary/blob/main/doc/appstore/privacy.md` |
| PSL_SUPPORT_DATA_DELETION_BY_USER | DATA_DELETION_YES | **true** |
| PSL_SUPPORT_DATA_DELETION_BY_USER | DATA_DELETION_NO | — |
| PSL_SUPPORT_DATA_DELETION_BY_USER | DATA_DELETION_NO_AUTO_DELETED | — |
| PSL_DATA_DELETION_URL | — | *(gleiche URL wie oben)* |

> Begründung: Der `gdpr-export`-Dienst ermöglicht vollständige Kontolöschung inkl. aller Firestore-Dokumente (DSGVO-Compliance).

---

## Abschnitt 4: Sonstige allgemeine Fragen

| Question ID | Antwort |
|---|---|
| PSL_DATA_COLLECTION_COMPLIES_FAMILY_POLICY | — (leer lassen, keine Kinder-Zielgruppe) |
| PSL_INDEPENDENTLY_VALIDATED | — (keine MASA-Prüfung) |
| PSL_UPI_BADGE_OPT_IN | — |
| PSL_HAS_OUTSIDE_APP_ACCOUNTS | — (nein, Konten werden in der App erstellt) |

---

## Abschnitt 5: Erhobene Datentypen

Nur die folgenden Datentypen werden erhoben. Alle anderen bleiben **leer (nicht ausgewählt)**.

| Kategorie | Datentyp | Question ID | Erhoben? |
|---|---|---|---|
| Personenbezogene Daten | Nutzer-IDs | PSL_USER_ACCOUNT | **✓** |
| Personenbezogene Daten | E-Mail-Adresse | PSL_EMAIL | **✓** (nur bei Google-Anmeldung) |
| Audiodateien | Sprach- oder Tonaufnahmen | PSL_AUDIO | **✓** (ephemer) |
| App-Aktivitäten | Andere von Nutzern erstellte Inhalte | PSL_USER_GENERATED_CONTENT | **✓** |
| Alle anderen Kategorien | — | — | **Nicht erhoben** |

---

## Abschnitt 6: Datennutzung je Typ

### PSL_USER_ACCOUNT — Nutzer-IDs

| Frage | Antwort |
|---|---|
| Erhoben / Geteilt | **Erhoben** (`PSL_DATA_USAGE_ONLY_COLLECTED = true`) |
| Sitzungsspezifisch (ephemer)? | **false** (wird persistent in Firebase gespeichert) |
| Erforderlich / Optional | **Erforderlich** (`PSL_DATA_USAGE_USER_CONTROL_REQUIRED = true`) |
| Zweck der Erhebung | **Funktionen der App** (`PSL_APP_FUNCTIONALITY = true`), **Kontoverwaltung** (`PSL_ACCOUNT_MANAGEMENT = true`) |
| Zweck der Weitergabe | — (wird nicht geteilt) |

> Die Firebase UID verknüpft Tagebucheinträge mit dem Nutzer. Ohne sie ist kein Datenzugriff möglich.

---

### PSL_EMAIL — E-Mail-Adresse

| Frage | Antwort |
|---|---|
| Erhoben / Geteilt | **Erhoben** (`PSL_DATA_USAGE_ONLY_COLLECTED = true`) |
| Sitzungsspezifisch (ephemer)? | **false** |
| Erforderlich / Optional | **Optional** (`PSL_DATA_USAGE_USER_CONTROL_OPTIONAL = true`) |
| Zweck der Erhebung | **Kontoverwaltung** (`PSL_ACCOUNT_MANAGEMENT = true`) |
| Zweck der Weitergabe | — (wird nicht geteilt) |

> Nur erhoben, wenn der Nutzer sich mit Google anmeldet (OAuth). Bei anonymer Anmeldung wird keine E-Mail erhoben.

---

### PSL_AUDIO — Sprach- oder Tonaufnahmen

| Frage | Antwort |
|---|---|
| Erhoben / Geteilt | **Erhoben** (`PSL_DATA_USAGE_ONLY_COLLECTED = true`) |
| Sitzungsspezifisch (ephemer)? | **true** — Audiobytes werden ausschließlich im RAM verarbeitet und nie auf Disk oder in Object Storage geschrieben |
| Erforderlich / Optional | **Erforderlich** (`PSL_DATA_USAGE_USER_CONTROL_REQUIRED = true`) |
| Zweck der Erhebung | **Funktionen der App** (`PSL_APP_FUNCTIONALITY = true`) |
| Zweck der Weitergabe | — (wird nicht geteilt) |

> Die Sprachaufnahme ist der Kernmechanismus der App (Diktat → Transkription → Tagebucheintrag). Audio wird per HTTPS/WebSocket an den ai-proxy-Dienst übertragen, dort in RAM transkribiert und danach verworfen.

---

### PSL_USER_GENERATED_CONTENT — Nutzergenerierte Inhalte

| Frage | Antwort |
|---|---|
| Erhoben / Geteilt | **Erhoben** (`PSL_DATA_USAGE_ONLY_COLLECTED = true`) |
| Sitzungsspezifisch (ephemer)? | **false** (Tagebuchtext wird in Firestore + lokalem SQLite persistiert) |
| Erforderlich / Optional | **Erforderlich** (`PSL_DATA_USAGE_USER_CONTROL_REQUIRED = true`) |
| Zweck der Erhebung | **Funktionen der App** (`PSL_APP_FUNCTIONALITY = true`) |
| Zweck der Weitergabe | — (wird nicht geteilt) |

> Enthält: normalisiertes Transkript, KI-generierter Tagebuchtext (bodyMarkdown), Stimmungseinschätzung (mood/moodScore), Themen und Folgefragen. Gespeichert in Cloud Firestore (eu-eur3, EU) und Drift SQLite lokal auf dem Gerät.

---

## Abschnitt 7: Nicht erhobene Daten (explizit leer lassen)

| Kategorie | Datentypen |
|---|---|
| Personenbezogene Daten | Name, Adresse, Telefonnummer, Ethnische Zugehörigkeit, Politische/Religiöse Überzeugungen, Sexuelle Orientierung, Sonstige |
| Finanzdaten | Alle (keine In-App-Käufe, kein Payment) |
| Standort | Ungefährer Standort, Genauer Standort |
| Surfen im Web | Browserverlauf |
| Nachrichten | E-Mails, SMS/MMS, In-App-Mitteilungen |
| Fotos und Videos | Fotos, Videos |
| Gesundheit und Fitness | Gesundheitsdaten, Fitnessdaten |
| Kontakte | Kontakte |
| Kalender | Kalendertermine |
| App-Informationen | Absturzprotokolle, Diagnosedaten (kein Crashlytics/Analytics eingebunden) |
| Dateien und Dokumente | Dateien und Dokumente |
| App-Aktivitäten | App-Interaktionen, Suchverlauf, Installierte Apps, Andere Aktionen |
| Geräte-IDs | Geräte- oder andere IDs |

---

## Hinweise für die Play Console

1. **Import via CSV:** Die Original-CSV-Datei kann im Play Console unter "Datensicherheit → Importieren" hochgeladen werden. Nur Zeilen mit `true` im `Response value`-Feld werden als ausgewählt gewertet.

2. **Audio-Ephemeralität:** Google definiert "sitzungsspezifisch" als: Daten werden nicht über die Sitzung hinaus gespeichert. Da wir Audiobytes nur im RAM verarbeiten und nie persistieren, ist `PSL_DATA_USAGE_EPHEMERAL = true` für `PSL_AUDIO` korrekt.

3. **Anonyme Auth:** Firebase Anonymous Auth generiert eine Firebase UID (Nutzer-ID), aber keine E-Mail. Die UID fällt unter `PSL_USER_ACCOUNT`, nicht unter `PSL_DEVICE_ID`.

4. **Drittanbieter:** Der ai-proxy sendet Audio an Google Cloud Speech-to-Text (Chirp 3, EU) und Tagebuchtext an Vertex AI Gemini. Diese Weitergabe erfolgt zur App-Funktionalität, nicht zu Werbezwecken. Google als Auftragsverarbeiter fällt nicht unter "Daten teilen" im Play-Store-Sinne (nur externe Empfänger außerhalb der Datenschutzrichtlinie zählen als "geteilt").
