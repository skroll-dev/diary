# gdpr-export

FastAPI service for DSGVO compliance (Art. 17 & 20 DSGVO):
- `POST /export/request` — exports all user Firestore data as a ZIP
- `DELETE /account` — deletes the user's Auth account and all Firestore data
- `POST /admin/cleanup-anonymous-users` — deletes anonymous Auth accounts older than 5 days (Cloud Scheduler only)

Auto-deployed to Cloud Run (`europe-west3`) on push to `main` via [deploy-gdpr-export.yml](../.github/workflows/deploy-gdpr-export.yml).

---

## Local development

```bash
python -m venv .venv && .venv\Scripts\pip install -r requirements.txt   # Windows
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt      # macOS/Linux

# Run (port 8081 to avoid conflict with ai-proxy on 8080)
ENV=development .venv/bin/uvicorn app.main:app --reload --port 8081
```

Required env vars (create a `.env` or export in shell):

| Variable | Example | Notes |
|---|---|---|
| `ENV` | `development` | Skips App Check; omit in production |
| `GOOGLE_APPLICATION_CREDENTIALS` | `./credentials.json` | Service account key for local auth; not needed in Cloud Run |

---

## One-time GCP setup

Run these commands once after the project is first deployed. Requires `gcloud` authenticated with Owner/Editor on `diary-6fa61`.

### 1. Create Artifact Registry repository

```bash
gcloud artifacts repositories create gdpr-export \
  --repository-format=docker \
  --location=europe-west3 \
  --project=diary-6fa61
```

### 2. Deploy the service

Push a commit touching `gdpr-export/` to `main` — CI will build and deploy automatically.
Or trigger it manually:

```bash
gcloud run deploy gdpr-export \
  --source gdpr-export/ \
  --region europe-west3 \
  --no-allow-unauthenticated \
  --project diary-6fa61
```

### 3. Create a dedicated service account for Cloud Scheduler

```bash
gcloud iam service-accounts create scheduler-gdpr-export \
  --display-name="Cloud Scheduler → gdpr-export" \
  --project=diary-6fa61
```

Grant it permission to invoke the Cloud Run service:

```bash
gcloud run services add-iam-policy-binding gdpr-export \
  --region=europe-west3 \
  --member="serviceAccount:scheduler-gdpr-export@diary-6fa61.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --project=diary-6fa61
```

### 4. Get the Cloud Run service URL

```bash
gcloud run services describe gdpr-export \
  --region=europe-west3 \
  --project=diary-6fa61 \
  --format="value(status.url)"
```

Export it for use in the next step:

```bash
export SERVICE_URL=$(gcloud run services describe gdpr-export \
  --region=europe-west3 --project=diary-6fa61 --format="value(status.url)")
```

### 5. Create the Cloud Scheduler job

Runs daily at 03:00 Europe/Berlin. Authenticates via OIDC so Cloud Run accepts the call.

```bash
gcloud scheduler jobs create http cleanup-anonymous-users \
  --location=europe-west3 \
  --schedule="0 3 * * *" \
  --time-zone="Europe/Berlin" \
  --uri="${SERVICE_URL}/admin/cleanup-anonymous-users" \
  --http-method=POST \
  --oidc-service-account-email="scheduler-gdpr-export@diary-6fa61.iam.gserviceaccount.com" \
  --oidc-token-audience="${SERVICE_URL}" \
  --project=diary-6fa61
```

To trigger a manual test run:

```bash
gcloud scheduler jobs run cleanup-anonymous-users \
  --location=europe-west3 \
  --project=diary-6fa61
```

---

## Security model

The `/admin/cleanup-anonymous-users` endpoint is protected at two layers:

1. **Cloud Run IAM** — `--no-allow-unauthenticated` rejects requests without a valid OIDC token issued to the `scheduler-gdpr-export` service account.
2. **Header check** — the endpoint rejects any request missing the `X-CloudScheduler-JobName` header, which Cloud Scheduler always attaches automatically.

The `/export/request` and `/DELETE /account` endpoints are protected by Firebase ID token verification (`Authorization: Bearer <token>`).
