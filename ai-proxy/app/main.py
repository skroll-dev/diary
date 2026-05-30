"""
ai-proxy – KI-Orchestrierungsdienst
Endpunkte:
  POST /transcribe   – Audio → Transkript (Cloud Speech-to-Text Chirp)
  POST /generate     – Transkript → Eintrag + Folgefragen (Gemini 2.0 Flash)
  POST /merge        – Eintrag + neues Transkript → erweiterter Eintrag (Gemini 2.0 Flash)
"""
import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv
load_dotenv()

import structlog
from fastapi import FastAPI, Request

class _TeeLogger:
    """Writes structlog output to stdout and optionally a file."""
    def __init__(self, file_path: str | None = None) -> None:
        self._file = open(file_path, "a", encoding="utf-8") if file_path else None

    def _write(self, message: str) -> None:
        print(message, flush=True)
        if self._file:
            print(message, file=self._file, flush=True)

    def __getattr__(self, name: str):
        return self._write


class _TeeLoggerFactory:
    def __init__(self, file_path: str | None = None) -> None:
        self._logger = _TeeLogger(file_path)

    def __call__(self, *args: object) -> _TeeLogger:
        return self._logger


def _configure_logging() -> None:
    log_file = os.environ.get("LOG_FILE")
    min_level = os.environ.get("LOG_LEVEL", "info").lower()
    structlog.configure(
        processors=[
            structlog.stdlib.add_log_level,
            structlog.processors.TimeStamper(fmt="%Y-%m-%d %H:%M:%S"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.ExceptionRenderer(),
            structlog.dev.ConsoleRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            {"debug": 10, "info": 20, "warning": 30, "error": 40}.get(min_level, 20)
        ),
        logger_factory=_TeeLoggerFactory(log_file),
        cache_logger_on_first_use=True,
    )


_configure_logging()
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
    allow_methods=["*"],
    allow_headers=["*"],
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
