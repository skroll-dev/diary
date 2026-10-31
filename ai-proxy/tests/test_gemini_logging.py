import asyncio
from types import SimpleNamespace

import pytest
from structlog.testing import capture_logs

from app.services import gemini

DIARY_TEXT = "Heute war ich beim Arzt wegen meiner Diagnose"


def _response(text: str):
    part = SimpleNamespace(text=text, thought=False)
    candidate = SimpleNamespace(
        content=SimpleNamespace(parts=[part]),
        finish_reason=SimpleNamespace(name="STOP"),
    )
    return SimpleNamespace(
        candidates=[candidate],
        text=text,
        usage_metadata=SimpleNamespace(candidates_token_count=1, total_token_count=2),
    )


class _FakeModel:
    reply = ""

    def __init__(self, *args, **kwargs):
        pass

    async def generate_content_async(self, *args, **kwargs):
        return _response(self.reply)


@pytest.mark.parametrize(
    ("call", "reply"),
    [
        (lambda: gemini.normalize_transcript(DIARY_TEXT), DIARY_TEXT),
        (lambda: gemini.generate_entry(DIARY_TEXT), f'{{"body_markdown": "{DIARY_TEXT}"}}'),
        (lambda: gemini.merge_entry(DIARY_TEXT, DIARY_TEXT, []), f'{{"body_markdown": "{DIARY_TEXT}"}}'),
    ],
)
def test_info_logs_contain_no_diary_content(monkeypatch, call, reply):
    monkeypatch.setattr(gemini, "GenerativeModel", _FakeModel)
    monkeypatch.setattr(_FakeModel, "reply", reply)

    with capture_logs() as logs:
        asyncio.run(call())

    above_debug = [entry for entry in logs if entry["log_level"] != "debug"]
    assert above_debug
    assert DIARY_TEXT not in str(above_debug)


def test_parse_error_log_contains_no_diary_content():
    with capture_logs() as logs, pytest.raises(ValueError):
        gemini._extract_json(f"{{not json: {DIARY_TEXT}}}")

    above_debug = [entry for entry in logs if entry["log_level"] != "debug"]
    assert above_debug
    assert DIARY_TEXT not in str(above_debug)
