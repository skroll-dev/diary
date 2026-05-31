"""
WebSocket endpoint for streaming audio transcription.
Client sends binary audio chunks, then the text message "done".
Server responds with {"transcript": "...", "duration_seconds": ...} and closes.
"""
import os
import structlog
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.services.auth import verify_app_check_token
from app.services.speech import transcribe_audio

log = structlog.get_logger()
router = APIRouter()


@router.websocket("/ws")
async def transcribe_ws(websocket: WebSocket, token: str | None = None):
    if os.environ.get("ENV") != "development":
        if not verify_app_check_token(token):
            await websocket.close(code=4001)
            return

    await websocket.accept()
    chunks: list[bytes] = []

    try:
        while True:
            msg = await websocket.receive()
            if msg.get("bytes"):
                chunks.append(msg["bytes"])
            elif msg.get("text") == "done":
                break
    except WebSocketDisconnect:
        return

    if not chunks:
        await websocket.send_json({"error": "Keine Audiodaten empfangen"})
        await websocket.close()
        return

    audio_bytes = b"".join(chunks)
    log.info("transcribe_ws", size_bytes=len(audio_bytes), chunks=len(chunks))

    try:
        result = await transcribe_audio(audio_bytes)
        await websocket.send_json({
            "transcript": result["transcript"],
            "duration_seconds": result["duration_seconds"],
        })
    except Exception as exc:
        log.error("transcribe_ws_error", error=str(exc))
        await websocket.send_json({"error": "Transkription fehlgeschlagen"})

    await websocket.close()
