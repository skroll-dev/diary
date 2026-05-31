"""
Gemini 2.0 Flash via Vertex AI
Region: europe-west3 (Frankfurt)
Prompts A + B aus MVP-Konzept §9
"""

import json
import os
import re
import structlog
import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig

log = structlog.get_logger()

GCP_PROJECT = os.environ["GCP_PROJECT"]
GCP_REGION = os.environ.get("GCP_REGION", "europe-west3")
MODEL = "gemini-2.5-flash"

vertexai.init(project=GCP_PROJECT, location=GCP_REGION)


class GeminiBlockedError(ValueError):
    """Raised when Gemini returns no content (safety filter or empty candidate)."""


def _require_text(response, fn_name: str) -> str:
    """Extract text from a Gemini response, raising GeminiBlockedError if no content."""
    candidate = response.candidates[0] if response.candidates else None
    if not candidate or not getattr(candidate.content, "parts", None):
        finish = candidate.finish_reason.name if candidate and candidate.finish_reason else "UNKNOWN"
        log.warning("gemini_blocked", fn=fn_name, finish_reason=finish)
        raise GeminiBlockedError(f"Gemini response blocked (finish_reason={finish})")
    return response.text


def _extract_json(text: str) -> dict:
    """Parse JSON from Gemini response, stripping markdown fences if present."""
    cleaned = re.sub(r"^```(?:json)?\s*\n?", "", text.strip())
    cleaned = re.sub(r"\n?```\s*$", "", cleaned)
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start != -1 and end != -1:
        cleaned = cleaned[start : end + 1]
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as e:
        log.error("gemini_json_parse_error", error=str(e), raw_response=text)
        raise


_GENERATION_CONFIG = GenerationConfig(
    response_mime_type="application/json",
    temperature=0.7,
    max_output_tokens=8192,
)

_SYSTEM_PROMPT_GENERATE = """Du bist Mathias, ein zurückhaltender, warmherziger Tagebuch-Assistent.
Aus dem rohen Sprachtranskript des Nutzers formst du einen Tagebucheintrag in der Ich-Form,
in seiner Sprache, mit seiner Wortwahl. Du fügst KEINE Informationen hinzu, die nicht im
Transkript stehen. Du glättest Füllwörter, ordnest Gedanken chronologisch und brichst lange
Sätze auf.

Gib AUSSCHLIESSLICH valides JSON zurück:
{
  "body_markdown": "1-3 Absätze, ich-Form, max. 250 Wörter",
  "mood": "happy" | "calm" | "neutral" | "tense" | "sad" | "mixed",
  "mood_score": Zahl zwischen -1.0 und +1.0,
  "follow_up_questions": [
    "Genau eine offene Frage, keine Ja/Nein-Frage",
    "Bezieht sich auf etwas Konkretes aus dem Eintrag",
    "Dritte Frage geht in die Tiefe, nicht in die Breite"
  ],
  "topics": [
    {
      "title": "Thema in 2-4 Wörtern",
      "text": "Vollständiger Text zu diesem Thema in der Ich-Form — alle relevanten Inhalte aus dem Transkript, nichts weglassen, keine Kürzungen",
      "follow_up_hint": "Eine spezifische Vertiefungsfrage für genau dieses Thema, max. 15 Wörter"
    }
  ]
}

Regeln für topics:
- Ein Topic pro erkennbarem Thema oder Ereignis im Transkript (min. 1, max. 5)
- title: prägnant, keine Verben (z.B. \"Meeting mit Tim\", \"Spaziergang abends\")
- text: vollständiger Ich-Form-Text für dieses Kapitel — ALLE relevanten Details aus dem Transkript, KEIN Kürzen
- follow_up_hint: konkret auf dieses Thema bezogen, nicht allgemein

Regeln für die follow_up_questions:
- Keine Ratschläge, keine Therapie-Phrasen
- Keine Frage darf mit \"Wie fühlst du dich?\" beginnen
- Greife konkrete Wörter aus dem Eintrag auf
- Maximal 15 Wörter pro Frage"""

_SYSTEM_PROMPT_MERGE = """Du bist Mathias. Der Nutzer hat heute bereits einen Eintrag verfasst
und gerade weitere Gedanken diktiert – meist als Antwort auf eine deiner Folgefragen.
Integriere die neuen Inhalte ORGANISCH in den bestehenden Eintrag: Dopplungen entfernen,
chronologisch ordnen, gleicher Ton. Generiere danach 2-3 NEUE Folgefragen, die noch nicht
beantwortet wurden.

Gib AUSSCHLIESSLICH valides JSON in exakt dieser Struktur zurück:
{
  "body_markdown": "Vollständiger Eintrag in Ich-Form, alle Inhalte integriert",
  "mood": "happy" | "calm" | "neutral" | "tense" | "sad" | "mixed",
  "mood_score": Zahl zwischen -1.0 und +1.0,
  "follow_up_questions": ["Neue Frage 1", "Neue Frage 2"],
  "topics": [
    {
      "title": "Thema in 2-4 Wörtern",
      "text": "Vollständiger Text zu diesem Thema in der Ich-Form — alle relevanten Inhalte, NICHTS kürzen",
      "follow_up_hint": "Eine spezifische Vertiefungsfrage für genau dieses Thema"
    }
  ]
}"""


async def generate_entry(transcript: str, language: str = "de") -> dict:
    log.info("gemini_call", fn="generate_entry", input=transcript)
    model = GenerativeModel(MODEL, system_instruction=_SYSTEM_PROMPT_GENERATE)
    response = await model.generate_content_async(
        transcript,
        generation_config=_GENERATION_CONFIG,
    )
    text = _require_text(response, "generate_entry")
    candidate = response.candidates[0]
    finish_reason = candidate.finish_reason.name if candidate.finish_reason else "UNKNOWN"
    usage = response.usage_metadata
    log.info("gemini_response", fn="generate_entry", finish_reason=finish_reason,
             output_tokens=usage.candidates_token_count,
             total_tokens=usage.total_token_count,
             output=text)
    return _extract_json(text)


_SYSTEM_PROMPT_NORMALIZE = """Du bearbeitest ein rohes Sprachtranskript leicht:
- Entferne Füllwörter und satzeinleitende Partikel (ähm, äh, also, halt, ne, genau, sozusagen, eigentlich, irgendwie, ja, naja)
- Bilde vollständige, fließende Sätze — ergänze implizit gemeinte Verbindungswörter (dann, aber, und, danach) wo sie fehlen
- Strukturiere Sätze um, wenn es den Lesefluss verbessert — die inhaltliche Reihenfolge bleibt erhalten
- Verwende durchgehend Perfekt für vergangene Ereignisse (z.B. „sind gegangen", „haben gemacht") — kein Plusquamperfekt, kein Präteritum
- Korrigiere offensichtliche Spracherkennungsfehler und Großschreibung
- Erfinde KEINE neuen Inhalte — nur was klar gemeint war darf ergänzt werden
- Kürze NICHT

Gib ausschließlich den bereinigten Text zurück — kein JSON, keine Erklärungen, keine Überschriften."""


async def normalize_transcript(transcript: str) -> str:
    log.info("gemini_call", fn="normalize_transcript", input=transcript)
    model = GenerativeModel(MODEL, system_instruction=_SYSTEM_PROMPT_NORMALIZE)
    config = GenerationConfig(temperature=0.2, max_output_tokens=2048)
    response = await model.generate_content_async(transcript, generation_config=config)
    try:
        text = _require_text(response, "normalize_transcript")
    except GeminiBlockedError:
        log.warning("gemini_normalize_fallback", reason="blocked, returning original")
        return transcript
    log.info("gemini_response", fn="normalize_transcript", output=text)
    return text.strip()


async def merge_entry(
    existing_entry: str,
    new_transcript: str,
    previous_questions: list[str],
    language: str = "de",
) -> dict:
    log.info("gemini_call", fn="merge_entry", existing_len=len(existing_entry), new_transcript=new_transcript)
    model = GenerativeModel(MODEL, system_instruction=_SYSTEM_PROMPT_MERGE)
    user_message = f"""BESTEHENDER EINTRAG:
{existing_entry}

NEUE GEDANKEN (Transkript):
{new_transcript}

BISHERIGE FOLGEFRAGEN (nicht wiederholen):
{chr(10).join(f"- {q}" for q in previous_questions)}"""

    response = await model.generate_content_async(
        user_message,
        generation_config=_GENERATION_CONFIG,
    )
    text = _require_text(response, "merge_entry")
    log.info("gemini_response", fn="merge_entry", output=text)
    return _extract_json(text)
