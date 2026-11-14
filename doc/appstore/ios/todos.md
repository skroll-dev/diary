# App Store resubmission checklist

Rejection: version 1.0 (39), reviewed 2026-10-27, guidelines 4.8 and 2.1.
Do these in order. `[x]` means done. The backend is live; the Flutter changes are still **uncommitted** on your machine.

## 1. Finish the backend deploy

- [x] Deploy `ai-proxy` and `gdpr-export` (commit `c07b0fa`).
- [x] Deploy the Firestore rules.
- [x] Confirm production logs are clean: `gemini_response` shows `output_chars` and no text.
- [x] Confirm real recordings still work on the current apps.
- [ ] Commit and push the remaining changes, Flutter included, once the device tests in step 4 pass. Pushing `flutter/` deploys the web app.

## 2. Apple Developer and Firebase consoles

- [x] **developer.apple.com → Identifiers → `com.diary.skroll.app`:** enable **Sign in with Apple**, then regenerate the provisioning profile (or let Xcode's automatic signing do it). Without this the build won't sign.
- [x] **Firebase console → Authentication → Sign-in method → Apple:** enable it. iOS needs no Services ID or key.
- [x] **developer.apple.com → Services → Sign in with Apple for Email Communication:** register the email address `noreply@diary-6fa61.firebaseapp.com` (its domain already has an SPF record). Without this, emails to Hide My Email addresses don't arrive.

## 2a. Move diary data to the EU

The original `(default)` Firestore database was in `nam5` (USA), and a database's location can't be changed. On 2026-11-14 it was backed up locally, deleted, recreated in `europe-west3` with delete protection, and refilled: all 68 entries match the backup. Apps only know the name `(default)`, so no app update is needed.

- [x] Local backup: `~/Documents/diary-firestore-backups/2026-11-14/` (see its `README.md`).
- [x] Recreate `(default)` in `europe-west3`, restore the data, deploy `firestore.rules`.
- [ ] Test on a device: create an entry, then check it appears under `(default)` in the Firebase console.
- [x] Weekly backups (Sundays, kept 98 days) now run on `(default)`; the schedule on `diary-eu` is removed.
- [ ] Optional, after the first `(default)` backup exists: delete the stale copy `diary-eu` with `firebase firestore:databases:delete diary-eu --project diary-6fa61`. Its two existing backups stay until they expire.
- [ ] Delete the local backup folder once you no longer need it. It holds diary text unencrypted outside FileVault.

## 3. Update the legal documents

Ask a lawyer if unsure, especially about the points below.

### Decide first

- [x] **Minimum age: use 18 everywhere.** `terms.html` says 18 but lets a parent accept for a minor, and `privacy_*.html` section 14 says 16. Google's Service Specific Terms (section 20(d)) forbid generative AI in an app directed at, or likely to be used by, anyone under 18, and Google can suspend the service for a suspected violation. Check this with your lawyer.
- [x] **Crash reports:** the policy says they contain no diary content and may be processed outside the EU. Confirm both before publishing.
- [x] **Training claim:** section 6 says content is not used to train public AI models. Check it against the Google Cloud terms. I kept it out of the reply to Apple until you've confirmed it.

### HTML files

- [x] `privacy_de.html`, `privacy_en.html` and `terms.html` are updated locally: sign-in providers, photos, Crashlytics, US sign-in data, no subscriptions, age 18.
- [ ] `privacy.md` is an older copy and wasn't updated. It isn't published; update or delete it.

### `data_safety_answers.md` (Play, before the Android release)

- [ ] Section 7: take `Absturzprotokolle` out of "not collected" and delete `kein Crashlytics/Analytics eingebunden`. Crashlytics stays in the app. `Diagnosedaten` may stay there now that Analytics is gone.
- [ ] Section 7: take `Fotos` out of "not collected".
- [ ] Section 7: `Name` is no longer "not collected" if Google or Apple provide it.

- [ ] Google Play: set the target age group to 18+ in the app content settings.

### Publish

- [x] Upload `privacy_de.html`, `privacy_en.html` and `terms.html` to `https://silbenquiz.de/diary-web/`, now that step 2a is done. No workflow does this, and the app links there.

## 4. Build and test on a real iPhone

- [x] Bump the build number: `0.4.32+41`. Build 40 was uploaded too but still had the old English microphone text and a tracking text in `en.lproj`; **don't submit build 40**.
- [x] Archive and upload build 41 to App Store Connect (2026-11-15).
- [ ] Check these on TestFlight. None of them can be verified without a real device and the deployed backend:

**Sign-in**

- [ ] The sheet shows Google, Apple, email, in that order. Android and web show Google, email.
- [ ] Google still works: new account, existing account (switches accounts, history loads), cancel, sign out and back in.
- [ ] Apple, sharing your email: entries are kept.
- [ ] Apple with Hide My Email: a relay address appears in the profile.
- [ ] Apple ID that already has an account: no second prompt, history loads.
- [ ] Apple email that matches a Google account: clear message, no crash.
- [ ] Cancelling Apple's prompt: the sheet stays open with no error.
- [ ] Note whether the name arrives on first Apple sign-in. The app copes if it doesn't.

**Delete account**

- [ ] Apple account: Apple prompt, then deleted, and the app is gone from iOS Settings → Apple ID → Sign-In & Security.
- [ ] Cancelling that prompt: nothing is deleted.
- [ ] Google or email account: no Apple prompt.

**Consent**

- [ ] Fresh install: the sheet appears on the first mic tap and first long-press. Not now keeps you on the home screen and sends nothing.
- [ ] Settings → Privacy: withdraw, then the next recording asks again. Both legal links open.
- [ ] Update over the old build: the sheet appears once.

**Recording** (iOS and Android, German and English)

- [ ] 5 seconds of silence: a friendly message and no empty entry.
- [ ] 90 seconds of speech, previously broken: complete transcript.
- [ ] 6 minutes of speech, which crosses a stream rotation: complete transcript. Listen for a lost word at the 4:30 mark.
- [ ] Your first words aren't cut off.
- [ ] Airplane mode mid-recording: a clear error, and any confirmed text is offered for saving.
- [ ] Live text appears while speaking on iPhone and Android. This path was web-only until now.
- [ ] Add photos from the gallery.

## 5. App Store Connect

- [ ] **App Privacy:** tracking = **No**. If the old answers declared tracking, remove it.
  Declare, all linked to the user, none used for tracking, purpose App Functionality:

  | Category | Type |
  |---|---|
  | Contact Info | Email Address, Name |
  | User Content | Other User Content (diary text), Photos or Videos, Audio Data |
  | Identifiers | User ID |
  | Diagnostics | Crash Data |

  Audio isn't retained, so it may fall outside Apple's definition of "collected". Declare it anyway; it's the safer answer for a voice diary.
- [ ] **Age rating:** answer the questionnaire truthfully, then choose the higher **18+** rating, because the app's policy requires it. Don't add an in-app age check unless your lawyer says you need one.
- [ ] **Description:** paste the updated privacy paragraph from `meta_de.md` and `meta_en.md`. It now names Google.
- [ ] **Screenshots:** check that none shows the old trust line "Your data stays in the EU." on the sign-in sheet.
- [ ] **Sign-in details:** user `review@tester.com`. The password field needs a value; use `tester`.
- [ ] **Review Notes:** paste this:

  ```text
  Recording needs speech: tap the mic, say at least one full sentence in English or German, then tap again to stop. If you can't speak, long-press the mic to type an entry instead.

  The first time, the app asks for permission to send content to Google for AI processing. Tap Agree. You can withdraw this in Settings > Privacy.

  To test sign-in: tap Done on an entry, enter review@tester.com, tap Send link. Sign-in completes immediately and no email is sent. Sign in with Apple and Google are on the same screen.
  ```

## 6. Reply to App Review

Select the new build, submit it, and paste this into the App Store Connect message. It's accurate for the current code; re-read it if anything changes before you send it.

```text
Hello,

Thank you for your review. Here are the answers to both items.

Guideline 4.8 - Login Services
This version adds Sign in with Apple on the sign-in screen, next to Google and email sign-in. It is available wherever the app offers Google sign-in on iOS.

Guideline 2.1 - Information Needed
Yes, the app uses third-party services for its AI features. All of them are Google Cloud services used through our own Google Cloud account:

- Google Cloud Speech-to-Text (Chirp 3) transcribes voice recordings, in Google's EU multi-region.
- Gemini 2.5 Flash on Google Vertex AI (Frankfurt, europe-west3) cleans up the transcript and generates the structured diary entry.

Audio is processed in memory and is not stored by us.

Before any user content is sent, the app shows what is sent, that it goes to Google, and where it is processed, and asks for the user's explicit permission. Users can withdraw that permission at any time in Settings > Privacy, and the privacy policy is linked from both places.

Sign-in details and testing steps are in the App Review Notes.

Best regards
```

## 7. Move Cloud Logging to the EU (do before launch)

Until `c07b0fa`, diary text from testers and App Review went to the `_Default` log bucket in `global`. New logs contain no diary text. There are no production users and the history isn't needed, so the plan is to route logs to an EU bucket and delete the old ones.

- [x] Note the current sink, including its filter:
  ```bash
  gcloud logging sinks describe _Default --project=diary-6fa61
  ```
- [x] Create the EU bucket and check that `location` is `europe-west3`:
  ```bash
  gcloud logging buckets create eu-logs --location=europe-west3 --retention-days=30 --project=diary-6fa61
  gcloud logging buckets describe eu-logs --location=europe-west3 --project=diary-6fa61
  ```
- [x] Point the default sink at it, then check that the destination is `eu-logs` and the filter is unchanged:
  ```bash
  gcloud logging sinks update _Default logging.googleapis.com/projects/diary-6fa61/locations/europe-west3/buckets/eu-logs --project=diary-6fa61
  gcloud logging sinks describe _Default --project=diary-6fa61
  ```
- [x] Wait about 5 minutes, then confirm new logs arrive there:
  ```bash
  curl -s https://ai-proxy-918937960824.europe-west3.run.app/health
  gcloud logging read 'resource.labels.service_name="ai-proxy"' --project=diary-6fa61 --bucket=eu-logs --location=europe-west3 --view=_AllLogs --freshness=10m --limit=3 --format='value(timestamp,logName)'
  ```
  Repeat after a few minutes if it's empty. Don't continue until entries appear.
- [x] Delete the old logs. This can't be undone. `requests` is included because WebSocket URLs can contain ID tokens:
  ```bash
  gcloud logging logs delete run.googleapis.com/stdout --project=diary-6fa61
  gcloud logging logs delete run.googleapis.com/stderr --project=diary-6fa61
  gcloud logging logs delete run.googleapis.com/requests --project=diary-6fa61
  ```
- [x] Confirm the global bucket no longer holds them. This prints nothing when clean; deletion can take a little while. `run.googleapis.com/varlog/system` isn't part of this check: it holds Cloud Run's own instance events, not app output.
  ```bash
  gcloud logging read 'logName:("run.googleapis.com%2Fstdout" OR "run.googleapis.com%2Fstderr" OR "run.googleapis.com%2Frequests")' --project=diary-6fa61 --bucket=_Default --location=global --view=_AllLogs --freshness=31d --limit=5 --format='value(timestamp,logName)'
  ```

**Don't run this as part of the steps.** Rollback only, if logging ever breaks: it sends logs back to `global`.

```bash
gcloud logging sinks update _Default logging.googleapis.com/projects/diary-6fa61/locations/global/buckets/_Default --project=diary-6fa61
```

`_Default` and `_Required` stay in `global`. `_Default` then receives nothing new, and `_Required` holds Google's audit logs, not app output.

## After approval

- [ ] **Apple login on Android, before or with the Android launch.** Until then, Hide My Email users can't reach their diary on Android. It needs an Apple Services ID and key in Firebase, grouped under the iOS App ID so the same Apple ID reaches the same account, plus `revokeAccessToken` on account deletion. Button order stays Google, Apple, email.
- [ ] This repository is public, so the review password in `auth_sheet.dart` is public too, and anyone can sign in to those accounts. Remove the personal test addresses (`mblaich@test.de`, `skroll@test.de`), change their passwords, and keep no real data in them. Rotate the `review@tester.com` password after approval.
- [ ] `POST /transcribe/` can go once no build up to 39 is in use.
- [ ] The WebSocket ID token sits in the URL, so it can appear in request logs. Move it into the first message.
- [ ] GDPR export ZIPs under `exports/{uid}/` survive account deletion; `DELETE /account` should remove them too.
- [ ] `handleGoogleRedirectResult` has no callers, which looks like a web sign-in bug.
