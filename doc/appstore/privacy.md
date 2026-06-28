# Datenschutzerklärung

# Mein KI-Tagebuch – „Sprich, die KI schreibt."

Stand: Juni 2026 · Version 1.0

## 1\. Verantwortlicher

Verantwortlich für die Datenverarbeitung im Sinne der Datenschutz-Grundverordnung (DSGVO) ist:  
Mathias Blaich  
Gartenstraße 25  
75382 Althengstett

Deutschland

E-Mail: blaichmathias@gmail.com

## 2\. Überblick und Geltungsbereich

Diese Datenschutzerklärung informiert dich über Art, Umfang und Zweck der Verarbeitung personenbezogener Daten innerhalb der mobilen Anwendung „Mein KI-Tagebuch" (nachfolgend „App") sowie über deine Rechte.  
Die App ermöglicht es dir, frei in dein Smartphone zu sprechen. Deine Spracheingabe wird durch künstliche Intelligenz transkribiert und zu einem strukturierten Tagebucheintrag verarbeitet. Der Schutz deiner sehr persönlichen Inhalte ist dabei ein zentraler Grundsatz unserer technischen Architektur („Privacy by Design").

## 3\. Welche Daten wir verarbeiten

Konto- und Stammdaten: Konto-Kennung (User-ID), Authentifizierungsdaten  
Spracheingaben (Audio): Deine gesprochenen Aufnahmen während der Erstellung eines Eintrags  
Tagebuchinhalte: Transkribierter Text, generierter Eintrag, Stimmungs-Tags und \-Scores  
Nutzungs- und Gerätedaten: App-Version, Geräte-/Betriebssystemtyp, Fehler-/Absturzberichte, Zeitstempel  
Abonnementdaten: Status des Abonnements (aktiv/inaktiv) – die Zahlung selbst erfolgt über App Store / Google Play

## 4\. Spracheingabe und Zero-Disk-Policy

Zero-Disk-Policy: Deine Audioaufnahmen werden zu keinem Zeitpunkt dauerhaft auf unseren Servern oder Festplatten gespeichert. Das Audio wird ausschließlich im Arbeitsspeicher (RAM) verarbeitet und unmittelbar nach der Erstellung des Texteintrags rückstandslos verworfen.  
Gespeichert wird lediglich das Ergebnis der Verarbeitung – also der von dir freigegebene Tagebucheintrag in Textform sowie die zugehörigen Metadaten (z. B. Stimmungs-Tag). Die Original-Audiodatei verlässt diesen In-Memory-Prozess nicht.

## 5\. Besondere Kategorien personenbezogener Daten (Art. 9 DSGVO)

Tagebucheinträge können ihrer Natur nach sehr persönliche Informationen enthalten – etwa Angaben zu Gesundheit, religiösen oder weltanschaulichen Überzeugungen, politischen Meinungen oder zum Sexualleben. Solche Daten gelten als besondere Kategorien personenbezogener Daten im Sinne des Art. 9 DSGVO und genießen besonderen Schutz.  
Die Verarbeitung dieser Inhalte erfolgt ausschließlich auf Grundlage deiner ausdrücklichen Einwilligung gemäß Art. 9 Abs. 2 lit. a DSGVO. Diese Einwilligung holen wir vor der ersten Nutzung des KI-Funktionsumfangs gesondert in der App ein. Du kannst sie jederzeit mit Wirkung für die Zukunft widerrufen.

## 6\. Verarbeitung durch künstliche Intelligenz

Zur Erbringung des Kerndienstes setzen wir folgende KI-Dienste ein:

Spracherkennung (Transkription): Google Cloud Speech-to-Text (Chirp) wandelt deine Spracheingabe in Text um.  
Textstrukturierung: Das multimodale Modell Gemini 2.5 Flash (Google Cloud Vertex AI) formt aus dem Gesprochenen einen zusammenhängenden Eintrag, extrahiert die Stimmung und generiert ggf. Vertiefungsfragen.

Die Spracherkennung wird innerhalb der Google Cloud EU Multi-Region verarbeitet. Die Textstrukturierung findet in der Region europe-west3 (Frankfurt am Main) statt. Deine Inhalte werden nicht zum Training öffentlicher KI-Modelle verwendet.

## 7\. Empfänger / Auftragsverarbeiter

Zur Bereitstellung der App nutzen wir sorgfältig ausgewählte Dienstleister, mit denen Auftragsverarbeitungsverträge (Art. 28 DSGVO) bestehen:

Google Cloud Run – Backend-Verarbeitung (In-Memory) · Google · europe-west3  
Firebase – Authentifizierung, Datenbank, Synchronisation · Google · europe-west3  
Speech-to-Text (Chirp) – Audio-Transkription · Google · EU  
Gemini 2.5 Flash (Vertex AI) – Textstrukturierung & Analyse · Google · EU  
Apple App Store / Google Play – Abwicklung von Abonnements & Zahlungen · Apple / Google

Anbieter ist jeweils die Google Ireland Limited bzw. ggf. die Google LLC. Soweit eine Übermittlung in Drittländer erfolgt, ist diese durch geeignete Garantien (insbesondere EU-Standardvertragsklauseln) abgesichert.

## 8\. Rechtsgrundlagen

Art. 6 Abs. 1 lit. b DSGVO – Erfüllung des Nutzungsvertrags (Bereitstellung der App-Funktionen, Konto, Abonnement).  
Art. 9 Abs. 2 lit. a DSGVO – ausdrückliche Einwilligung für Tagebuchinhalte mit besonderem Schutzbedarf.  
Art. 6 Abs. 1 lit. f DSGVO – berechtigtes Interesse (z. B. Stabilität, Fehleranalyse, Sicherheit).  
Art. 6 Abs. 1 lit. c DSGVO – Erfüllung rechtlicher Verpflichtungen.

## 9\. Speicherort und Speicherdauer

Deine Tagebucheinträge und Kontodaten werden in der EU (Frankfurt, europe-west3) gespeichert. Zusätzlich werden Einträge lokal auf deinem Gerät gespeichert (SQLite-Datenbank); diese Daten verlassen dein Gerät nur zur Synchronisation mit der Cloud. Wir speichern deine Daten so lange, wie dein Konto besteht. Löschst du einzelne Einträge oder dein gesamtes Konto, werden die zugehörigen Daten gelöscht. Audioaufnahmen werden gemäß der Zero-Disk-Policy gar nicht erst dauerhaft gespeichert.

## 10\. Deine Rechte

Dir stehen nach der DSGVO folgende Rechte zu:

Auskunft über die verarbeiteten Daten (Art. 15\)  
Berichtigung unrichtiger Daten (Art. 16\)  
Löschung („Recht auf Vergessenwerden", Art. 17\)  
Einschränkung der Verarbeitung (Art. 18\)  
Datenübertragbarkeit – Export deiner Einträge (Art. 20\)  
Widerspruch gegen die Verarbeitung (Art. 21\)  
Widerruf erteilter Einwilligungen mit Wirkung für die Zukunft (Art. 7 Abs. 3\)

Zur Ausübung deiner Rechte genügt eine Nachricht an blaichmathias@gmail.com.

## 11\. Datensicherheit

Wir schützen deine Daten durch technische und organisatorische Maßnahmen. Die Übertragung erfolgt verschlüsselt (TLS), Daten im Ruhezustand werden verschlüsselt gespeichert (AES-256). Der Zugriff auf Verarbeitungssysteme ist auf das Notwendige beschränkt.

## 12\. Authentifizierung

Für die Anmeldung und Kontoverwaltung nutzen wir Firebase Authentication. Dabei werden deine Konto-Kennung und Authentifizierungsdaten verarbeitet, um dir einen sicheren Zugang zu deinen Einträgen zu ermöglichen.

## 13\. Abonnements und Zahlungen

Kostenpflichtige Funktionen werden als Abonnement angeboten. Der Kauf und die Abrechnung erfolgen ausschließlich über den Apple App Store bzw. Google Play. Wir erhalten keine vollständigen Zahlungsdaten (z. B. Kreditkartennummern), sondern lediglich Informationen über den Status deines Abonnements. Es gelten ergänzend die Datenschutzbestimmungen von Apple und Google.

## 14\. Minderjährige

Die App richtet sich nicht an Kinder. Personen unter 16 Jahren dürfen die App nur mit Einwilligung der Erziehungsberechtigten nutzen.

## 15\. Beschwerderecht bei der Aufsichtsbehörde

Du hast das Recht, dich bei einer Datenschutz-Aufsichtsbehörde zu beschweren. Zuständig ist in der Regel die Behörde deines Wohnsitzes oder unseres Sitzes:  
Der Landesbeauftragte für den Datenschutz und die Informationsfreiheit Baden-Württemberg  
www.baden-wuerttemberg.datenschutz.de

## 16\. Änderungen dieser Datenschutzerklärung

Wir passen diese Datenschutzerklärung an, sobald Änderungen an der App oder der Rechtslage dies erfordern. Die jeweils aktuelle Version ist stets an dieser Stelle abrufbar.

© 2026 Mathias Blaich · Mein KI-Tagebuch · Zuletzt aktualisiert im Juni 2026