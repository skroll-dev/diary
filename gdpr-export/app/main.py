"""
gdpr-export – DSGVO-Datenexport (Art. 20 DSGVO: Recht auf Datenübertragbarkeit)
Endpunkte:
  POST /export/request  – Nutzer fordert Export an; Job wird angestoßen
  DELETE /account       – Löscht alle Daten des Nutzers (Art. 17 DSGVO)
"""
import io
import json
import os
import zipfile
from datetime import datetime, timezone

import firebase_admin
import structlog
from fastapi import FastAPI, HTTPException, Header
from firebase_admin import auth, firestore, storage
from pydantic import BaseModel

log = structlog.get_logger()

firebase_admin.initialize_app()
db = firestore.client()

app = FastAPI(
    title="AI Tagebuch – gdpr-export",
    version="0.1.0",
    docs_url="/docs" if os.environ.get("ENV") != "production" else None,
)


# ── Auth Helper ────────────────────────────────────────────────────────────────

async def _get_uid(authorization: str) -> str:
    """Verifiziert den Firebase ID-Token und gibt die uid zurück."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Kein Bearer-Token")
    token = authorization.removeprefix("Bearer ")
    try:
        decoded = auth.verify_id_token(token)
        return decoded["uid"]
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Ungültiger Token") from exc


# ── Schemas ───────────────────────────────────────────────────────────────────

class ExportResponse(BaseModel):
    message: str
    export_url: str


class DeleteResponse(BaseModel):
    message: str
    deleted_at: str


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/export/request", response_model=ExportResponse)
async def request_export(authorization: str = Header(...)):
    uid = await _get_uid(authorization)
    log.info("export_requested", uid=uid)

    # Alle Einträge des Nutzers aus Firestore laden
    entries_ref = db.collection("users").document(uid).collection("entries")
    entries = [doc.to_dict() for doc in entries_ref.stream()]

    # ZIP im Speicher aufbauen
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("entries.json", json.dumps(entries, ensure_ascii=False, indent=2))

        # Pro Eintrag eine lesbare Markdown-Datei
        for entry in entries:
            date = entry.get("date", "unbekannt")
            body = entry.get("bodyMarkdown", "")
            questions = entry.get("followUpQuestions", [])
            mood = entry.get("mood", "")
            md = f"# {date}\n\n**Stimmung:** {mood}\n\n{body}\n\n"
            if questions:
                md += "## Offene Fragen\n" + "\n".join(f"- {q}" for q in questions)
            zf.writestr(f"entries/{date}.md", md)

    buffer.seek(0)

    # ZIP in Cloud Storage hochladen (temporär, 7 Tage)
    bucket = storage.bucket()
    blob_path = f"exports/{uid}/export_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}.zip"
    blob = bucket.blob(blob_path)
    blob.upload_from_file(buffer, content_type="application/zip")

    # Signed URL (7 Tage Gültigkeit)
    from datetime import timedelta
    signed_url = blob.generate_signed_url(expiration=timedelta(days=7), method="GET")

    log.info("export_ready", uid=uid, entries=len(entries))
    return ExportResponse(
        message=f"{len(entries)} Einträge exportiert. Download-Link gültig für 7 Tage.",
        export_url=signed_url,
    )


@app.delete("/account", response_model=DeleteResponse)
async def delete_account(authorization: str = Header(...)):
    uid = await _get_uid(authorization)
    log.info("account_deletion_requested", uid=uid)

    # Alle Einträge löschen
    entries_ref = db.collection("users").document(uid).collection("entries")
    for doc in entries_ref.stream():
        doc.reference.delete()

    # Nutzer-Dokument löschen
    db.collection("users").document(uid).delete()

    # Firebase Auth Account löschen
    auth.delete_user(uid)

    deleted_at = datetime.now(timezone.utc).isoformat()
    log.info("account_deleted", uid=uid, deleted_at=deleted_at)
    return DeleteResponse(
        message="Dein Account und alle Daten wurden vollständig gelöscht.",
        deleted_at=deleted_at,
    )
