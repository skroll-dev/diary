"""
Firebase App Check Token Verifikation
Schützt den KI-Proxy vor Missbrauch durch nicht-autorisierte Clients.
"""
import os
import firebase_admin
from firebase_admin import app_check
from fastapi import Header, HTTPException

_firebase_app = None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is None:
        _firebase_app = firebase_admin.initialize_app()
    return _firebase_app


async def verify_app_check(
    x_firebase_appcheck: str = Header(..., alias="X-Firebase-AppCheck"),
) -> None:
    """FastAPI Dependency – wirft 401 wenn der App-Check-Token ungültig ist."""
    if os.environ.get("ENV") == "development":
        # In der lokalen Entwicklung App-Check überspringen
        return

    try:
        app_check.verify_token(x_firebase_appcheck, app=_get_firebase_app())
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Ungültiger App-Check-Token") from exc
