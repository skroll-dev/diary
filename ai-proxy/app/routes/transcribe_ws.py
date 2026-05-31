"""
WebSocket endpoint for streaming audio transcription.
Client sends binary audio chunks, then the text message "done".
Server responds with {"transcript": "...", "duration_seconds": ...} and closes.
"""
import os
import struct
import structlog
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.services.auth import verify_id_token
from app.services.speech import transcribe_audio


_SAMPLE_RATE = 16000
_BYTES_PER_SAMPLE = 2  # 16-bit mono
_MAX_CHUNK_BYTES = _SAMPLE_RATE * _BYTES_PER_SAMPLE * 55  # 55s margin under the 60s API limit


def _pcm16_to_wav(pcm_bytes: bytes) -> bytes:
    data_size = len(pcm_bytes)
    header = struct.pack("<4sI4s", b"RIFF", 36 + data_size, b"WAVE")
    fmt = struct.pack(
        "<4sIHHIIHH",
        b"fmt ", 16, 1, 1, _SAMPLE_RATE,
        _SAMPLE_RATE * _BYTES_PER_SAMPLE, _BYTES_PER_SAMPLE, 16,
    )
    data_header = struct.pack("<4sI", b"data", data_size)
    return header + fmt + data_header + pcm_bytes


async def _transcribe_pcm16(pcm_bytes: bytes) -> dict:
    """Splits long PCM16 recordings into ≤55-second chunks to stay under Chirp 3's 60s limit."""
    if len(pcm_bytes) <= _MAX_CHUNK_BYTES:
        return await transcribe_audio(_pcm16_to_wav(pcm_bytes))

    parts = []
    total_duration = 0.0
    for offset in range(0, len(pcm_bytes), _MAX_CHUNK_BYTES):
        chunk = pcm_bytes[offset : offset + _MAX_CHUNK_BYTES]
        result = await transcribe_audio(_pcm16_to_wav(chunk))
        parts.append(result["transcript"])
        total_duration += result.get("duration_seconds", 0.0)

    return {
        "transcript": " ".join(filter(None, parts)),
        "duration_seconds": total_duration,
        "language_detected": "de",
    }


log = structlog.get_logger()
router = APIRouter()


@router.websocket("/ws")
async def transcribe_ws(websocket: WebSocket, token: str | None = None):
    if os.environ.get("ENV") != "development":
        if not verify_id_token(token):
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

    pcm_bytes = b"".join(chunks)
    log.info("transcribe_ws", size_bytes=len(pcm_bytes), chunks=len(chunks))

    try:
        result = await _transcribe_pcm16(pcm_bytes)
        await websocket.send_json({
            "transcript": result["transcript"],
            "duration_seconds": result["duration_seconds"],
        })
    except Exception as exc:
        log.error("transcribe_ws_error", error=str(exc))
        await websocket.send_json({"error": "Transkription fehlgeschlagen"})

    await websocket.close()
