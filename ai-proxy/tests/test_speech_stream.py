import asyncio
from types import SimpleNamespace

from app.services import speech


def _result(text: str, *, final: bool = True, end_seconds: float = 1.0):
    return SimpleNamespace(
        alternatives=[SimpleNamespace(transcript=text)],
        is_final=final,
        result_end_offset=SimpleNamespace(total_seconds=lambda: end_seconds),
    )


class _FakeClient:
    """Drains each stream's requests, then returns one final result per stream."""

    def __init__(self, *args, **kwargs):
        self.stream_audio: list[int] = []

    async def streaming_recognize(self, requests):
        audio_bytes = 0
        async for request in requests:
            audio_bytes += len(request.audio)
        self.stream_audio.append(audio_bytes)
        n = len(self.stream_audio)

        async def _responses():
            yield SimpleNamespace(results=[_result(f"part{n}", end_seconds=10.0)])

        return _responses()


def _run(chunks: list[bytes | None], monkeypatch) -> tuple[dict, _FakeClient]:
    client = _FakeClient()
    monkeypatch.setattr(speech, "SpeechAsyncClient", lambda **_: client)

    async def _main():
        queue: asyncio.Queue = asyncio.Queue()
        for chunk in chunks:
            queue.put_nowait(chunk)
        return await speech.stream_transcribe_audio(queue, sample_rate=16000)

    return asyncio.run(_main()), client


def test_short_recording_uses_one_stream(monkeypatch):
    result, client = _run([b"\0" * 32000, None], monkeypatch)

    assert result["transcript"] == "part1"
    assert client.stream_audio == [32000]


def test_long_recording_rotates_and_keeps_all_audio(monkeypatch):
    monkeypatch.setattr(speech, "_MAX_STREAM_SECONDS", 1)  # 32000 bytes at 16 kHz
    chunks: list[bytes | None] = [b"\0" * 16000 for _ in range(5)]

    result, client = _run([*chunks, None], monkeypatch)

    assert result["transcript"] == "part1 part2 part3"
    assert client.stream_audio == [32000, 32000, 16000]
    assert result["duration_seconds"] == 30.0


def test_stop_right_after_rotation_opens_no_empty_stream(monkeypatch):
    monkeypatch.setattr(speech, "_MAX_STREAM_SECONDS", 1)

    result, client = _run([b"\0" * 32000, None], monkeypatch)

    assert result["transcript"] == "part1"
    assert client.stream_audio == [32000]


def test_no_audio_opens_no_stream(monkeypatch):
    result, client = _run([None], monkeypatch)

    assert result["transcript"] == ""
    assert client.stream_audio == []
