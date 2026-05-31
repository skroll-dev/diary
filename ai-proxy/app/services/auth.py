"""
Firebase Auth ID Token Verifikation
Schützt den KI-Proxy vor unbefugtem Zugriff.
"""
import os
import firebase_admin
from firebase_admin import auth as fb_auth
from fastapi import Header, HTTPException

_firebase_app = None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is None:
        _firebase_app = firebase_admin.initialize_app()
    return _firebase_app


def verify_id_token(token: str | None) -> bool:
    """Verifies a Firebase Auth ID token string; returns True if valid."""
    if not token:
        return False
    try:
        fb_auth.verify_id_token(token, app=_get_firebase_app())
        return True
    except Exception:
        return False


async def verify_app_check(
    authorization: str | None = Header(None, alias="Authorization"),
) -> None:
    """FastAPI Dependency – wirft 401 wenn der Auth-Token fehlt oder ungültig ist."""
    if os.environ.get("ENV") == "development":
        return

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization-Token fehlt")

    token = authorization.removeprefix("Bearer ")
    try:
        fb_auth.verify_id_token(token, app=_get_firebase_app())
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Ungültiger Token") from exc
