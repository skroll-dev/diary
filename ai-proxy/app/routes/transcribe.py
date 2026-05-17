"""
POST /transcribe
Nimmt eine Audio-Datei (m4a/wav) entgegen, gibt das Roh-Transkript zurück.
"""
import structlog
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel

from app.services.speech import transcribe_audio
from app.services.auth import verify_app_check

log = structlog.get_logger()
router = APIRouter()


class TranscribeResponse(BaseModel):
    transcript: str
    duration_seconds: float
    language_detected: str


@router.post("/", response_model=TranscribeResponse)
async def transcribe(
    audio: UploadFile = File(...),
    _: None = Depends(verify_app_check),
):
    if audio.content_type not in ("audio/m4a", "audio/aac", "audio/wav", "audio/mpeg"):
        raise HTTPException(status_code=415, detail="Nicht unterstütztes Audio-Format")

    audio_bytes = await audio.read()
    if len(audio_bytes) > 10 * 1024 * 1024:  # 10 MB Limit
        raise HTTPException(status_code=413, detail="Audio-Datei zu groß (max. 10 MB)")

    log.info("transcribe_request", size_bytes=len(audio_bytes), content_type=audio.content_type)

    result = await transcribe_audio(audio_bytes, audio.content_type)
    return TranscribeResponse(**result)
