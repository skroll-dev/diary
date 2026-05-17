"""
ai-proxy – KI-Orchestrierungsdienst
Endpunkte:
  POST /transcribe   – Audio → Transkript (Cloud Speech-to-Text Chirp)
  POST /generate     – Transkript → Eintrag + Folgefragen (Gemini 2.0 Flash)
  POST /merge        – Eintrag + neues Transkript → erweiterter Eintrag (Gemini 2.0 Flash)
"""
import os
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.routes.transcribe import router as transcribe_router
from app.routes.entries import router as entries_router

log = structlog.get_logger()

GCP_PROJECT = os.environ.get("GCP_PROJECT", "")
GCP_REGION = os.environ.get("GCP_REGION", "europe-west3")


@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("ai-proxy starting", project=GCP_PROJECT, region=GCP_REGION)
    yield
    log.info("ai-proxy shutting down")


app = FastAPI(
    title="AI Tagebuch – ai-proxy",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs" if os.environ.get("ENV") != "production" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: auf Firebase Hosting Domain einschränken
    allow_methods=["POST"],
    allow_headers=["Authorization", "X-Firebase-AppCheck"],
)

app.include_router(transcribe_router, prefix="/transcribe", tags=["STT"])
app.include_router(entries_router, prefix="/entries", tags=["Entries"])


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    log.error("unhandled_exception", path=request.url.path, error=str(exc))
    return JSONResponse(status_code=500, content={"detail": "Interner Fehler"})
