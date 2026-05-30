"""
POST /entries/generate  – Prompt A: erstes Diktat → Eintrag
POST /entries/merge     – Prompt B: Ergänzungs-Diktat → erweiterter Eintrag
"""
from typing import Literal

import structlog
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.services.gemini import generate_entry, merge_entry, normalize_transcript
from app.services.auth import verify_app_check

log = structlog.get_logger()
router = APIRouter()

MoodType = Literal["happy", "calm", "neutral", "tense", "sad", "mixed"]


# ── Schemas ──────────────────────────────────────────────────────────────────

class NormalizeRequest(BaseModel):
    transcript: str = Field(..., min_length=5, max_length=8_000)


class NormalizeResponse(BaseModel):
    normalized_text: str


class GenerateRequest(BaseModel):
    transcript: str = Field(..., min_length=10, max_length=8_000)
    language: str = Field(default="de")


class MergeRequest(BaseModel):
    existing_entry: str = Field(..., min_length=10, max_length=5_000)
    new_transcript: str = Field(..., min_length=10, max_length=4_000)
    previous_questions: list[str] = Field(default_factory=list)
    language: str = Field(default="de")


class EntryResponse(BaseModel):
    body_markdown: str
    mood: MoodType
    mood_score: float = Field(..., ge=-1.0, le=1.0)
    follow_up_questions: list[str] = Field(..., min_length=2, max_length=3)


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/normalize", response_model=NormalizeResponse)
async def normalize(
    req: NormalizeRequest,
    _: None = Depends(verify_app_check),
):
    log.info("normalize_request", transcript_len=len(req.transcript))
    text = await normalize_transcript(req.transcript)
    return NormalizeResponse(normalized_text=text)


@router.post("/generate", response_model=EntryResponse)
async def generate(
    req: GenerateRequest,
    _: None = Depends(verify_app_check),
):
    log.info("generate_entry", transcript_len=len(req.transcript))
    result = await generate_entry(req.transcript, req.language)
    return EntryResponse(**result)


@router.post("/merge", response_model=EntryResponse)
async def merge(
    req: MergeRequest,
    _: None = Depends(verify_app_check),
):
    log.info("merge_entry", existing_len=len(req.existing_entry), new_len=len(req.new_transcript))
    result = await merge_entry(
        req.existing_entry,
        req.new_transcript,
        req.previous_questions,
        req.language,
    )
    return EntryResponse(**result)
