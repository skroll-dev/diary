"""
POST /images/upload  – Bild hochladen (resized full + thumb Variante)
POST /images/delete  – Storage-Objekte löschen
"""
import structlog
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from google.cloud.exceptions import NotFound
from pydantic import BaseModel

from app.services.auth import assert_owns_path, get_current_uid
from app.services.images import (
    ALLOWED_CONTENT_TYPES,
    MAX_IMAGES_PER_ENTRY,
    MAX_UPLOAD_BYTES,
    build_object_paths,
    is_valid_date,
    new_upload_token,
    process_upload,
)
from app.services.storage import get_bucket

log = structlog.get_logger()
router = APIRouter()


# ── Schemas ──────────────────────────────────────────────────────────────────

class UploadImageResponse(BaseModel):
    full_path: str
    thumb_path: str
    width: int
    height: int
    thumb_width: int
    thumb_height: int


class DeleteImagesRequest(BaseModel):
    object_paths: list[str]


class DeleteImagesResponse(BaseModel):
    deleted: int


# ── Routes ───────────────────────────────────────────────────────────────────

@router.post("/upload", response_model=UploadImageResponse)
async def upload_image(
    image: UploadFile = File(...),
    date: str = Form(...),
    entry_ordinal: int = Form(...),
    entry_id: str = Form(""),
    existing_image_count: int = Form(0),
    uid: str = Depends(get_current_uid),
):
    if not is_valid_date(date):
        raise HTTPException(status_code=400, detail="Ungültiges Datum")
    if entry_ordinal < 1:
        raise HTTPException(status_code=400, detail="Ungültige entry_ordinal")
    if existing_image_count >= MAX_IMAGES_PER_ENTRY:
        raise HTTPException(
            status_code=422,
            detail=f"Maximal {MAX_IMAGES_PER_ENTRY} Fotos pro Eintrag",
        )
    if image.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=415, detail="Nicht unterstütztes Bildformat")

    raw = await image.read()
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Bild zu groß")

    log.info("image_upload_request", uid=uid, entry_id=entry_id, bytes=len(raw))

    try:
        full_bytes, thumb_bytes, (fw, fh), (tw, th) = process_upload(raw)
    except Exception as exc:
        raise HTTPException(status_code=422, detail="Bild konnte nicht verarbeitet werden") from exc

    upload_token = new_upload_token()
    full_path, thumb_path = build_object_paths(
        uid=uid, date=date, entry_ordinal=entry_ordinal, upload_token=upload_token,
    )

    bucket = get_bucket()
    bucket.blob(full_path).upload_from_string(full_bytes, content_type="image/jpeg")
    bucket.blob(thumb_path).upload_from_string(thumb_bytes, content_type="image/jpeg")

    log.info(
        "image_uploaded",
        uid=uid,
        entry_id=entry_id,
        full_path=full_path,
        full_bytes=len(full_bytes),
        thumb_bytes=len(thumb_bytes),
    )
    return UploadImageResponse(
        full_path=full_path, thumb_path=thumb_path,
        width=fw, height=fh, thumb_width=tw, thumb_height=th,
    )


@router.post("/delete", response_model=DeleteImagesResponse)
async def delete_images(
    req: DeleteImagesRequest,
    uid: str = Depends(get_current_uid),
):
    for path in req.object_paths:
        assert_owns_path(uid, path)

    bucket = get_bucket()
    deleted = 0
    for path in req.object_paths:
        try:
            bucket.blob(path).delete()
            deleted += 1
        except NotFound:
            pass  # bereits gelöscht – idempotent

    log.info("images_deleted", uid=uid, count=deleted)
    return DeleteImagesResponse(deleted=deleted)
