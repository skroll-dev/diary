# Test Account for App Reviewers

The app uses passwordless email login (magic link). A dedicated test account bypasses the email flow for reviewers.

## How to log in

The sign-in sheet appears when tapping **Done** (German: **Fertig**) on the diary entry screen after completing a recording. It can also be triggered optionally from the main screen. It offers Google, Apple (iOS only) and email, in that order.

**Primary flow:**

1. On the main screen, tap the mic button. The first time, the AI consent sheet appears: tap **Agree**.
2. Tap the mic button to start recording, say at least one full sentence, and tap again to stop. Alternatively, long-tap the mic button to enter text manually.
3. Review the generated diary entry on the topics screen.
4. Tap **Done** — the sign-in sheet appears.
5. Enter `review@tester.com` in the email field and tap **Send link** (German: **Link senden**) — sign-in completes immediately, no email is sent.

- Other mails: skroll@test.de, mblaich@test.de

## Notes

- This account is a permanent Firebase Auth user (`diary-6fa61`) with email/password credentials.
- All other email addresses go through the normal magic link flow.
- The bypass is hardcoded in `flutter/lib/features/auth/presentation/auth_sheet.dart`.
