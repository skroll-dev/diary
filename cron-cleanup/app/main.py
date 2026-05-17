"""
cron-cleanup – Cloud Run Job
Löscht Audio-Dateien aus Cloud Storage, die älter als AUDIO_RETENTION_HOURS sind.
Wird täglich per Cloud Scheduler getriggert.

Umgebungsvariablen:
  GCP_PROJECT            – GCP-Projekt-ID
  STORAGE_BUCKET         – Name des Firebase-Storage-Buckets
  AUDIO_RETENTION_HOURS  – Aufbewahrungszeit in Stunden (default: 2)
  AUDIO_PREFIX           – Pfad-Präfix der Audio-Files in GCS (default: "audio/")
"""
import os
import sys
from datetime import datetime, timedelta, timezone

import firebase_admin
import structlog
from firebase_admin import storage
from google.cloud import storage as gcs

log = structlog.get_logger()

BUCKET_NAME = os.environ.get("STORAGE_BUCKET", "")
AUDIO_PREFIX = os.environ.get("AUDIO_PREFIX", "audio/")
RETENTION_HOURS = int(os.environ.get("AUDIO_RETENTION_HOURS", "2"))


def main() -> int:
    firebase_admin.initialize_app()
    client = gcs.Client()
    bucket = client.bucket(BUCKET_NAME)

    cutoff = datetime.now(timezone.utc) - timedelta(hours=RETENTION_HOURS)
    log.info(
        "cleanup_start",
        bucket=BUCKET_NAME,
        prefix=AUDIO_PREFIX,
        retention_hours=RETENTION_HOURS,
        cutoff=cutoff.isoformat(),
    )

    blobs = list(bucket.list_blobs(prefix=AUDIO_PREFIX))
    deleted = 0
    errors = 0

    for blob in blobs:
        if blob.time_created and blob.time_created < cutoff:
            try:
                blob.delete()
                log.info("blob_deleted", name=blob.name, created=blob.time_created.isoformat())
                deleted += 1
            except Exception as exc:
                log.error("blob_delete_failed", name=blob.name, error=str(exc))
                errors += 1

    log.info("cleanup_done", deleted=deleted, errors=errors, total_scanned=len(blobs))
    return 1 if errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
