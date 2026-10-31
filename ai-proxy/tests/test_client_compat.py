"""Wire contract of apps already in the field. Installed native builds up to 39
use POST /transcribe/, and the web app streams 44.1 kHz audio over the
WebSocket. Keep these passing as long as such clients exist.
"""
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.routes import transcribe, transcribe_ws
from app.services import speech
from app.services.auth import verify_app_check

_WEB_BATCH = b"\0" * 176400  # ~2 s at 44.1 kHz, as the web client batches


def _result(text: str, *, final: bool, end_seconds: float = 2.0):
    return SimpleNamespace(
        alternatives=[SimpleNamespace(transcript=text)],
        is_final=final,
        result_end_offset=SimpleNamespace(total_seconds=lambda: end_seconds),
    )


class _FakeGoogle:
    def __init__(self):
        self.stream_config = None
        self.recognize_request = None
        self.fail = False

    async def recognize(self, request):
        self.recognize_request = request
        return SimpleNamespace(results=[_result("hallo welt", final=True)])

    async def streaming_recognize(self, requests):
        async for request in requests:
            if self.stream_config is None:
                self.stream_config = request.streaming_config

        async def _responses():
            if self.fail:
                raise RuntimeError("google down")
            yield SimpleNamespace(results=[_result("hallo", final=False)])
            yield SimpleNamespace(results=[_result("hallo welt", final=True)])

        return _responses()


@pytest.fixture
def google(monkeypatch):
    fake = _FakeGoogle()
    monkeypatch.setattr(speech, "SpeechAsyncClient", lambda **_: fake)
    monkeypatch.setattr(transcribe_ws, "verify_id_token", lambda token: token == "valid")
    return fake


@pytest.fixture
def client(google):
    app = FastAPI()
    app.include_router(transcribe.router, prefix="/transcribe")
    app.include_router(transcribe_ws.router, prefix="/transcribe")
    app.dependency_overrides[verify_app_check] = lambda: None
    return TestClient(app)


def _collect(ws) -> list[dict]:
    messages = []
    while True:
        message = ws.receive_json()
        messages.append(message)
        if message.get("type") == "final" or "error" in message:
            return messages


def test_native_build_posts_audio_and_gets_transcript(client, google):
    response = client.post(
        "/transcribe/",
        files={"audio": ("recording.wav", b"RIFF" + b"\0" * 2000, "audio/wav")},
        data={"denoise": "0", "language": "de"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "transcript": "hallo welt",
        "duration_seconds": 2.0,
        "language_detected": "de",
    }
    assert google.recognize_request.config.language_codes == ["de-DE"]


def test_native_build_keeps_size_and_type_errors(client):
    too_big = b"\0" * (10 * 1024 * 1024 + 1)

    assert client.post("/transcribe/", files={"audio": ("a.wav", too_big, "audio/wav")}).status_code == 413
    assert client.post("/transcribe/", files={"audio": ("a.txt", b"x", "text/plain")}).status_code == 415


def test_web_client_streams_and_gets_its_messages_in_order(client, google):
    with client.websocket_connect("/transcribe/ws?token=valid&denoise=0&sr=44100&language=de") as ws:
        ws.send_bytes(_WEB_BATCH)
        ws.send_bytes(_WEB_BATCH)
        ws.send_text("done")
        messages = _collect(ws)

    assert messages == [
        {"type": "interim", "text": "hallo"},
        {"type": "segment", "text": "hallo welt"},
        {"type": "final", "transcript": "hallo welt", "duration_seconds": 2.0},
    ]
    assert google.stream_config.config.explicit_decoding_config.sample_rate_hertz == 44100
    assert google.stream_config.config.language_codes == ["de-DE"]


def test_client_omitting_sample_rate_still_gets_44100(client, google):
    with client.websocket_connect("/transcribe/ws?token=valid") as ws:
        ws.send_bytes(_WEB_BATCH)
        ws.send_text("done")
        _collect(ws)

    assert google.stream_config.config.explicit_decoding_config.sample_rate_hertz == 44100


def test_streaming_failure_reports_the_same_error(client, google):
    google.fail = True

    with client.websocket_connect("/transcribe/ws?token=valid") as ws:
        ws.send_bytes(_WEB_BATCH)
        ws.send_text("done")
        assert _collect(ws) == [{"error": "Transkription fehlgeschlagen"}]


def test_invalid_token_is_rejected(client):
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect("/transcribe/ws?token=wrong"):
            pass

    assert exc.value.code == 4001
