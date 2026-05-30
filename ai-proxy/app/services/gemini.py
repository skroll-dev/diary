"""
Gemini 2.0 Flash via Vertex AI
Region: europe-west3 (Frankfurt)
Prompts A + B aus MVP-Konzept §9
"""

import json
import os
import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig

GCP_PROJECT = os.environ["GCP_PROJECT"]
GCP_REGION = os.environ.get("GCP_REGION", "europe-west3")
MODEL = "gemini-2.5-flash"

vertexai.init(project=GCP_PROJECT, location=GCP_REGION)

_GENERATION_CONFIG = GenerationConfig(
    response_mime_type="application/json",
    temperature=0.7,
    max_output_tokens=1024,
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
  ]
}

Regeln für die Fragen:
- Keine Ratschläge, keine Therapie-Phrasen
- Keine Frage darf mit \"Wie fühlst du dich?\" beginnen
- Greife konkrete Wörter aus dem Eintrag auf
- Maximal 15 Wörter pro Frage"""

_SYSTEM_PROMPT_MERGE = """Du bist Mathias. Der Nutzer hat heute bereits einen Eintrag verfasst
und gerade weitere Gedanken diktiert – meist als Antwort auf eine deiner Folgefragen.
Integriere die neuen Inhalte ORGANISCH in den bestehenden Eintrag: Dopplungen entfernen,
chronologisch ordnen, gleicher Ton. Generiere danach 2-3 NEUE Folgefragen, die noch nicht
beantwortet wurden.

Gib JSON in der gleichen Struktur wie zuvor zurück."""


async def generate_entry(transcript: str, language: str = "de") -> dict:
    model = GenerativeModel(MODEL, system_instruction=_SYSTEM_PROMPT_GENERATE)
    response = await model.generate_content_async(
        transcript,
        generation_config=_GENERATION_CONFIG,
    )
    return json.loads(response.text)


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
    model = GenerativeModel(MODEL, system_instruction=_SYSTEM_PROMPT_NORMALIZE)
    config = GenerationConfig(temperature=0.2, max_output_tokens=2048)
    response = await model.generate_content_async(transcript, generation_config=config)
    return response.text.strip()


async def merge_entry(
    existing_entry: str,
    new_transcript: str,
    previous_questions: list[str],
    language: str = "de",
) -> dict:
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
    return json.loads(response.text)
