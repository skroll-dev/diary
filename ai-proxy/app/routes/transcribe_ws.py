"""
WebSocket endpoint for streaming audio transcription.
Client sends binary PCM16 chunks (16 kHz mono), then the text "done".
Server responds with:
  {"type": "interim",  "text": "..."}                    — partial result
  {"type": "segment",  "text": "..."}                    — confirmed segment
  {"type": "final",    "transcript": "...", "duration_seconds": 0.0}
  {"error": "..."}                                        — on failure
"""
import asyncio
import os
import struct
import structlog
from datetime import datetime
from pathlib import Path
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.services.auth import verify_id_token
from app.services.speech import stream_transcribe_audio

log = structlog.get_logger()
router = APIRouter()

_IS_DEV = os.environ.get("ENV") == "development"
_DEBUG_DIR = Path(__file__).parent.parent.parent / "tmp"


def _pcm16_to_wav(pcm: bytes, sample_rate: int = 16000, channels: int = 1) -> bytes:
    data_size = len(pcm)
    header = struct.pack("<4sI4s", b"RIFF", 36 + data_size, b"WAVE")
    fmt = struct.pack(
        "<4sIHHIIHH",
        b"fmt ", 16, 1, channels, sample_rate,
        sample_rate * channels * 2, channels * 2, 16,
    )
    return header + fmt + struct.pack("<4sI", b"data", data_size) + pcm


def _save_debug_wav(chunks: list[bytes], *, sample_rate: int = 44100) -> None:
    if not chunks:
        return
    _DEBUG_DIR.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = _DEBUG_DIR / f"ws_audio_{ts}_{sample_rate}hz.wav"
    path.write_bytes(_pcm16_to_wav(b"".join(chunks), sample_rate=sample_rate))
    log.info("debug_audio_saved", path=str(path), size_bytes=path.stat().st_size, sample_rate=sample_rate)


@router.websocket("/ws")
async def transcribe_ws(
    websocket: WebSocket,
    token: str | None = None,
    denoise: bool = True,
    sr: int = 44100,
):
    if not _IS_DEV:
        if not verify_id_token(token):
            await websocket.close(code=4001)
            return

    await websocket.accept()

    audio_queue: asyncio.Queue[bytes | None] = asyncio.Queue()
    chunks_received = 0
    debug_chunks: list[bytes] = [] if _IS_DEV else None  # type: ignore[assignment]

    async def _receive_loop() -> None:
        nonlocal chunks_received
        try:
            while True:
                msg = await websocket.receive()
                if msg.get("bytes"):
                    chunk = msg["bytes"]
                    await audio_queue.put(chunk)
                    chunks_received += 1
                    if _IS_DEV:
                        debug_chunks.append(chunk)
                elif msg.get("text") == "done":
                    break
        except WebSocketDisconnect:
            pass
        finally:
            await audio_queue.put(None)

    receive_task = asyncio.create_task(_receive_loop())

    async def _on_interim(text: str) -> None:
        await websocket.send_json({"type": "interim", "text": text})

    async def _on_segment(text: str) -> None:
        await websocket.send_json({"type": "segment", "text": text})

    try:
        result = await stream_transcribe_audio(
            audio_queue, on_interim=_on_interim, on_segment=_on_segment,
            denoise_audio=denoise, sample_rate=sr,
        )
        log.info("transcribe_ws", chunks=chunks_received, denoise=denoise, sr=sr)
        if _IS_DEV:
            _save_debug_wav(debug_chunks, sample_rate=sr)
        await websocket.send_json({
            "type": "final",
            "transcript": result["transcript"],
            "duration_seconds": result["duration_seconds"],
        })
    except Exception as exc:
        log.error("transcribe_ws_error", error=str(exc))
        if _IS_DEV:
            _save_debug_wav(debug_chunks, sample_rate=sr)
        await websocket.send_json({"error": "Transkription fehlgeschlagen"})
    finally:
        receive_task.cancel()
        try:
            await receive_task
        except asyncio.CancelledError:
            pass
        await websocket.close()
