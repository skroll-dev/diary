# Diary – Agent Instructions

Dieses Projekt entwickelt eine **Business-Model-Idee + passende Mobile App** mit Fokus auf den Google-Stack (Cloud Run, Firestore, Firebase Auth/Hosting/Crashlytics, Gemini, BigQuery) und Flutter/Dart auf der Client-Seite.

## Skills

Im Verzeichnis `.agents/skills/` sind **Open Agent Skills** installiert. Vor jeder relevanten Aufgabe MUSST du den passenden Skill identifizieren und seine `SKILL.md` lesen, bevor du Code schreibst. Skills sind nach Domain gruppiert:

### Google Cloud & Firebase
| Skill | Wann nutzen |
| --- | --- |
| `cloud-run-basics` | Cloud Run Services, Jobs, Worker Pools deployen |
| `firebase-basics` | Firebase CLI Setup, Auth, Projektinitialisierung, `google-services.json`/`GoogleService-Info.plist` |
| `firebase-firestore` | **Immer aktivieren bei Firestore-Nutzung.** Datenbanken, Security Rules, Datenmodelle, Queries, Indexes |
| `firebase-auth-basics` | Sign-in (Google, Email/Password, Phone, Anonymous), User Management |
| `firebase-crashlytics` | Crash Reporting einrichten und nutzen |
| `firebase-hosting-basics` | Klassisches Hosting für statische Sites / SPAs |
| `firebase-app-hosting-basics` | App Hosting für Next.js/Angular Apps mit Backend |
| `bigquery-basics` | BigQuery Datasets, Tables, SQL, BigQuery ML, Gemini Integration |
| `gemini-api` | Gemini auf Vertex AI / Agent Platform mit Google Gen AI SDK |

### Flutter (App-Architektur, UI, Networking, Localization, Routing)
| Skill | Wann nutzen |
| --- | --- |
| `flutter-apply-architecture-best-practices` | Neues Projekt strukturieren – UI/Logic/Data Layered Approach |
| `flutter-setup-declarative-routing` | `go_router` für Deep Linking, Browser History |
| `flutter-setup-localization` | `flutter_localizations` + `intl`, `l10n.yaml` |
| `flutter-build-responsive-layout` | Adaptive Layouts (LayoutBuilder, MediaQuery, Expanded/Flexible) |
| `flutter-fix-layout-issues` | RenderFlex Overflow, Unbounded Constraints |
| `flutter-implement-json-serialization` | `fromJson`/`toJson` mit `dart:convert` |
| `flutter-use-http-package` | REST-Calls (GET/POST/PUT/DELETE) |
| `flutter-add-widget-preview` | Interaktive Previews mit `previews.dart` |
| `flutter-add-widget-test` | Component-Tests mit `WidgetTester` |
| `flutter-add-integration-test` | Flutter Driver + `integration_test` Package |

### Dart (Tests, Tooling, Pakete)
| Skill | Wann nutzen |
| --- | --- |
| `dart-build-cli-app` | CLI-Tools / Skripte in Dart |
| `dart-add-unit-test` | Unit-Tests mit `package:test` |
| `dart-generate-test-mocks` | Mocks mit `mockito` + `build_runner` |
| `dart-collect-coverage` | Coverage mit LCOV-Report |
| `dart-migrate-to-checks-package` | Von `matcher` zu `checks` migrieren |
| `dart-run-static-analysis` | `dart analyze` + `dart fix --apply` |
| `dart-fix-runtime-errors` | Stack Trace → Fix → Hot Reload verifizieren |
| `dart-resolve-package-conflicts` | Konflikte bei `pub get` lösen |
| `dart-use-pattern-matching` | Switch Expressions, Pattern Matching |

### iOS-spezifisch
| Skill | Wann nutzen |
| --- | --- |
| `xcode-project-setup` | `.pbxproj` modifizieren, Swift Packages hinzufügen (z.B. Firebase, Alamofire) |

### Meta / Sonstige
| Skill | Wann nutzen |
| --- | --- |
| `frontend-design` | Hochwertige Web/UI-Designs (Landing Pages, Komponenten) – nicht für native Flutter UI |
| `find-skills` | Weitere Skills aus dem Ökosystem suchen und installieren |

## Workflow-Regel

Bei einer Aufgabe wie *„setze Firestore-Collections für User-Profile auf"* gehst du so vor:

1. Identifiziere relevante Skills → hier: `firebase-firestore` (Pflicht), evtl. `firebase-basics`, `firebase-auth-basics`.
2. Lies die jeweiligen `SKILL.md` mit dem Read-Tool:
   `/Users/sebastian.kroll/Documents/git/diary/.agents/skills/firebase-firestore/SKILL.md`
3. Folge den Anweisungen darin (oft inkl. Verifikationsschritten, Anti-Patterns, Exit-Kriterien).
4. Erst dann Code schreiben.

## Tech-Stack-Entscheidungen

- **Mobile-Framework:** Flutter (Dart) – sichtbar an den installierten Flutter/Dart-Skills
- **Backend:** Cloud Run (Container) + Firestore (DB)
- **Auth:** Firebase Auth
- **Crash-Reporting:** Firebase Crashlytics
- **Analytics:** Google Analytics (Firebase SDK) – noch ohne dedizierten Skill, offizielle Doku nutzen
- **AI:** Gemini via Vertex AI / Agent Platform
- **Monetarisierung:** AdMob – noch ohne dedizierten Skill, offizielle SDK-Doku nutzen
- **Data Warehouse:** BigQuery (optional, für Analytics-Aggregation)

## Was noch fehlt (kein installierter Skill)

- AdMob-Integration in Flutter (`google_mobile_ads` Package nutzen)
- Google Analytics 4 für mobile (Firebase Analytics SDK reicht)
- App Store / Play Store Submission
