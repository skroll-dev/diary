1. Profil erstellen:
   wie heisse ich, wer ist meine familie. Wo wohne ich, wie alt bin ich....
   Glossar ?
2. TopicsReviewScreen:
   Topics sollten mehr als nur überschreiften sein. Fragen zur erörterung schon im Topic anzeigen
   Orginalteste sollten korrigierbar, löschbar sein.
   Orginaltexte
3. Entry Screen
   Not existing at all
4. Xcode → open flutter/ios/Runner.xcworkspace → Runner target → Signing & Capabilities → + → Associated Domains → add applinks:diary-6fa61.firebaseapp.com
   (This is what makes the email sign-in link open the app instead of Safari — cannot be done via file editing)

gcloud scheduler jobs create http cleanup-anonymous-users \
 --location=europe-west3 \
 --schedule="0 3 \* \* \*" \
 --time-zone="Europe/Berlin" \
 --uri="https://gdpr-export-z4vu65i3aa-ey.a.run.app/admin/cleanup-anonymous-users" \
 --http-method=POST \
 --oidc-service-account-email="scheduler-gdpr-export@diary-6fa61.iam.gserviceaccount.com" \
 --oidc-token-audience="https://gdpr-export-z4vu65i3aa-ey.a.run.app" \
 --project=diary-6fa61
