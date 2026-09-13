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
    """Extract text from a Gemini response, raising GeminiBlockedError if no content.

    Filters out thinking/reasoning parts (thought=True) so that gemini-2.5-flash
    thinking tokens don't contaminate the returned text and break JSON parsing.
    """
    candidate = response.candidates[0] if response.candidates else None
    if not candidate or not getattr(candidate.content, "parts", None):
        finish = candidate.finish_reason.name if candidate and candidate.finish_reason else "UNKNOWN"
        log.warning("gemini_blocked", fn=fn_name, finish_reason=finish)
        raise GeminiBlockedError(f"Gemini response blocked (finish_reason={finish})")
    all_parts = candidate.content.parts
    output_parts = [
        p.text for p in all_parts
        if not getattr(p, "thought", False) and getattr(p, "text", None)
    ]
    thinking_parts = [p for p in all_parts if getattr(p, "thought", False)]
    if thinking_parts:
        thinking_chars = sum(len(getattr(p, "text", "") or "") for p in thinking_parts)
        log.info("gemini_thinking_filtered", fn=fn_name, thinking_parts=len(thinking_parts), thinking_chars=thinking_chars)
    if output_parts:
        return "".join(output_parts)
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

_SYSTEM_PROMPT_GENERATE_DE = """Du bist Mein KI-Tagebuch, ein zurückhaltender, warmherziger Tagebuch-Assistent.
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
    "Offene Frage, keine Ja/Nein-Frage",
    "Bezieht sich auf etwas Konkretes aus dem Eintrag"
  ],
  "topics": [
    {
      "title": "Thema in 2-4 Wörtern",
      "text": "Vollständiger Text zu diesem Thema in der Ich-Form — alle relevanten Inhalte aus dem Transkript, nichts weglassen, keine Kürzungen"
    }
  ],
  "tags": ["Kurzwort1", "Kurzwort2"]
}

Regeln für topics:
- Ein Topic pro erkennbarem Thema oder Ereignis im Transkript (min. 1, max. 5)
- title: prägnant, keine Verben (z.B. \"Meeting mit Tim\", \"Spaziergang abends\")
- text: vollständiger Ich-Form-Text für dieses Kapitel — ALLE relevanten Details aus dem Transkript, KEIN Kürzen

Regeln für tags:
- 1-4 kurze Schlüsselwörter (Nomen, keine Verben, max. 2 Wörter pro Tag)
- Bevorzuge vorhandene Tags aus existing_tags (falls im Transkript übergeben) — erfinde nur neue wenn kein vorhandener passt
- Beispiele: "Familie", "Arbeit", "Natur", "Sport", "Freunde"

Regeln für die follow_up_questions:
- Keine Ratschläge, keine Therapie-Phrasen
- Keine Frage darf mit \"Wie fühlst du dich?\" beginnen
- Greife konkrete Wörter aus dem Eintrag auf
- Maximal 15 Wörter pro Frage
- 1-3 Fragen, nur wenn sie dem Eintrag echten Mehrwert bieten
- Wenn keine sinnvollen Fragen entstehen, gib ein leeres Array zurück: []"""

_SYSTEM_PROMPT_GENERATE_EN = """You are My AI-Diary, a reserved, warm-hearted diary assistant.
From the user's raw voice transcript you shape a diary entry in the first person,
in their own language and word choice. You add NO information that isn't in the
transcript. You smooth out filler words, order thoughts chronologically, and break up
long sentences.

Return ONLY valid JSON:
{
  "body_markdown": "1-3 paragraphs, first person, max. 250 words",
  "mood": "happy" | "calm" | "neutral" | "tense" | "sad" | "mixed",
  "mood_score": number between -1.0 and +1.0,
  "follow_up_questions": [
    "Open question, not a yes/no question",
    "Refers to something concrete from the entry"
  ],
  "topics": [
    {
      "title": "Topic in 2-4 words",
      "text": "Full first-person text for this topic — all relevant content from the transcript, omit nothing, no shortening"
    }
  ],
  "tags": ["Keyword1", "Keyword2"]
}

Rules for topics:
- One topic per identifiable theme or event in the transcript (min. 1, max. 5)
- title: concise, no verbs (e.g. \"Meeting with Tim\", \"Evening walk\")
- text: full first-person text for this chapter — ALL relevant details from the transcript, NO shortening

Rules for tags:
- 1-4 short keywords (nouns, no verbs, max. 2 words per tag)
- Prefer existing tags from existing_tags (if provided) — only invent new ones if none fit
- Examples: "Family", "Work", "Nature", "Sport", "Friends"

Rules for follow_up_questions:
- No advice, no therapy-speak
- No question may start with \"How do you feel?\"
- Pick up concrete words from the entry
- Maximum 15 words per question
- 1-3 questions, only if they add real value to the entry
- If no meaningful questions arise, return an empty array: []"""

_SYSTEM_PROMPT_MERGE_DE = """Du bist Mein KI-Tagebuch. Der Nutzer hat heute bereits einen Eintrag verfasst
und gerade weitere Gedanken diktiert – meist als Antwort auf eine deiner Folgefragen.
Integriere die neuen Inhalte ORGANISCH in den bestehenden Eintrag: Dopplungen entfernen,
chronologisch ordnen, gleicher Ton. Generiere danach neue Folgefragen, die noch nicht
beantwortet wurden — nur wenn sie echten Mehrwert bieten.

Gib AUSSCHLIESSLICH valides JSON in exakt dieser Struktur zurück:
{
  "body_markdown": "Vollständiger Eintrag in Ich-Form, alle Inhalte integriert",
  "mood": "happy" | "calm" | "neutral" | "tense" | "sad" | "mixed",
  "mood_score": Zahl zwischen -1.0 und +1.0,
  "follow_up_questions": ["Neue Frage 1", "Neue Frage 2"],
  "topics": [
    {
      "title": "Thema in 2-4 Wörtern",
      "text": "Vollständiger Text zu diesem Thema in der Ich-Form — alle relevanten Inhalte, NICHTS kürzen"
    }
  ],
  "tags": ["Kurzwort1", "Kurzwort2"]
}

follow_up_questions: 0-3 Fragen, keine Ja/Nein-Fragen, konkret auf den Eintrag bezogen, max. 15 Wörter pro Frage. Wenn keine sinnvollen Fragen entstehen, gib [] zurück.

tags: 1-4 kurze Schlüsselwörter (Nomen, keine Verben, max. 2 Wörter pro Tag). Bevorzuge vorhandene Tags aus existing_tags (falls übergeben) — erfinde nur neue wenn kein vorhandener passt."""

_SYSTEM_PROMPT_MERGE_EN = """You are My AI-Diary. The user has already written an entry today
and just dictated further thoughts — usually in response to one of your follow-up questions.
Integrate the new content ORGANICALLY into the existing entry: remove duplication,
order chronologically, keep the same tone. Then generate new follow-up questions that
haven't been answered yet — only if they add real value.

Return ONLY valid JSON in exactly this structure:
{
  "body_markdown": "Complete entry in first person, all content integrated",
  "mood": "happy" | "calm" | "neutral" | "tense" | "sad" | "mixed",
  "mood_score": number between -1.0 and +1.0,
  "follow_up_questions": ["New question 1", "New question 2"],
  "topics": [
    {
      "title": "Topic in 2-4 words",
      "text": "Full first-person text for this topic — all relevant content, NOTHING shortened"
    }
  ],
  "tags": ["Keyword1", "Keyword2"]
}

follow_up_questions: 0-3 questions, no yes/no questions, specific to the entry, max. 15 words per question. If no meaningful questions arise, return [].

tags: 1-4 short keywords (nouns, no verbs, max. 2 words per tag). Prefer existing tags from existing_tags (if provided) — only invent new ones if none fit."""

_GENERATE_PROMPTS = {"de": _SYSTEM_PROMPT_GENERATE_DE, "en": _SYSTEM_PROMPT_GENERATE_EN}
_MERGE_PROMPTS = {"de": _SYSTEM_PROMPT_MERGE_DE, "en": _SYSTEM_PROMPT_MERGE_EN}


def _tags_hint(existing_tags: list[str] | None, language: str) -> str:
    if not existing_tags:
        return ""
    label = "prefer these" if language == "en" else "bevorzuge diese"
    return f"\n\nexisting_tags ({label}): {existing_tags}"


async def generate_entry(transcript: str, language: str = "de", existing_tags: list[str] | None = None) -> dict:
    tags_hint = _tags_hint(existing_tags, language)
    log.info("gemini_call", fn="generate_entry", input=transcript)
    model = GenerativeModel(MODEL, system_instruction=_GENERATE_PROMPTS.get(language, _SYSTEM_PROMPT_GENERATE_DE))
    response = await model.generate_content_async(
        transcript + tags_hint,
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


_SYSTEM_PROMPT_NORMALIZE_DE = """Du bearbeitest ein rohes Sprachtranskript leicht:
- Entferne Füllwörter und satzeinleitende Partikel (ähm, äh, also, halt, ne, genau, sozusagen, eigentlich, irgendwie, ja, naja)
- Bilde vollständige, fließende Sätze — ergänze implizit gemeinte Verbindungswörter (dann, aber, und, danach) wo sie fehlen
- Strukturiere Sätze um, wenn es den Lesefluss verbessert — die inhaltliche Reihenfolge bleibt erhalten
- Verwende durchgehend Perfekt für vergangene Ereignisse (z.B. „sind gegangen", „haben gemacht") — kein Plusquamperfekt, kein Präteritum
- Korrigiere offensichtliche Spracherkennungsfehler und Großschreibung
- Erfinde KEINE neuen Inhalte — nur was klar gemeint war darf ergänzt werden
- Kürze NICHT

Gib ausschließlich den bereinigten Text zurück — kein JSON, keine Erklärungen, keine Überschriften."""

_SYSTEM_PROMPT_NORMALIZE_EN = """You lightly edit a raw voice transcript:
- Remove filler words and sentence-opening particles (um, uh, like, you know, I mean, sort of, kind of, actually, basically, so, well)
- Form complete, flowing sentences — add implied connecting words (then, but, and, afterwards) where they're missing
- Restructure sentences where it improves readability — the order of content stays the same
- Use natural, grammatically correct past tense throughout for past events
- Correct obvious speech-recognition errors and capitalization
- Do NOT invent new content — only add what was clearly meant
- Do NOT shorten

Return only the cleaned-up text — no JSON, no explanations, no headings."""

_NORMALIZE_PROMPTS = {"de": _SYSTEM_PROMPT_NORMALIZE_DE, "en": _SYSTEM_PROMPT_NORMALIZE_EN}


async def normalize_transcript(transcript: str, language: str = "de") -> str:
    log.info("gemini_call", fn="normalize_transcript", input=transcript)
    model = GenerativeModel(MODEL, system_instruction=_NORMALIZE_PROMPTS.get(language, _SYSTEM_PROMPT_NORMALIZE_DE))
    config = GenerationConfig(temperature=0.2, max_output_tokens=8192)
    response = await model.generate_content_async(transcript, generation_config=config)
    try:
        text = _require_text(response, "normalize_transcript")
    except GeminiBlockedError:
        log.warning("gemini_normalize_fallback", reason="blocked, returning original")
        return transcript
    candidate = response.candidates[0]
    finish_reason = candidate.finish_reason.name if candidate.finish_reason else "UNKNOWN"
    usage = response.usage_metadata
    log.info("gemini_response", fn="normalize_transcript", finish_reason=finish_reason,
             output_tokens=usage.candidates_token_count,
             total_tokens=usage.total_token_count,
             output=text)
    return text.strip()


async def merge_entry(
    existing_entry: str,
    new_transcript: str,
    previous_questions: list[str],
    language: str = "de",
    existing_tags: list[str] | None = None,
) -> dict:
    log.info("gemini_call", fn="merge_entry", existing_len=len(existing_entry), new_transcript=new_transcript)
    model = GenerativeModel(MODEL, system_instruction=_MERGE_PROMPTS.get(language, _SYSTEM_PROMPT_MERGE_DE))
    tags_hint = _tags_hint(existing_tags, language)
    if language == "en":
        user_message = f"""EXISTING ENTRY:
{existing_entry}

NEW THOUGHTS (transcript):
{new_transcript}

PREVIOUS FOLLOW-UP QUESTIONS (don't repeat):
{chr(10).join(f"- {q}" for q in previous_questions)}{tags_hint}"""
    else:
        user_message = f"""BESTEHENDER EINTRAG:
{existing_entry}

NEUE GEDANKEN (Transkript):
{new_transcript}

BISHERIGE FOLGEFRAGEN (nicht wiederholen):
{chr(10).join(f"- {q}" for q in previous_questions)}{tags_hint}"""

    last_exc: Exception | None = None
    for attempt in range(3):
        response = await model.generate_content_async(
            user_message,
            generation_config=_GENERATION_CONFIG,
        )
        text = _require_text(response, "merge_entry")
        log.info("gemini_response", fn="merge_entry", output=text)
        try:
            return _extract_json(text)
        except json.JSONDecodeError as exc:
            last_exc = exc
            log.warning("gemini_json_retry", fn="merge_entry", attempt=attempt, error=str(exc))
    raise last_exc
