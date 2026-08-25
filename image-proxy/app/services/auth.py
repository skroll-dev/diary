import firebase_admin
from fastapi import Header, HTTPException
from firebase_admin import auth as fb_auth

_firebase_app = None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is None:
        _firebase_app = firebase_admin.initialize_app()
    return _firebase_app


async def get_current_uid(
    authorization: str | None = Header(None, alias="Authorization"),
) -> str:
    """FastAPI Dependency – verifiziert den Firebase ID-Token und gibt die uid
    zurück. Diese uid ist die EINZIGE zulässige Quelle für Storage-Pfade –
    niemals eine vom Client mitgeschickte uid für Pfade verwenden.

    Anders als ai-proxys App-Check-Bypass gibt es hier KEINEN
    ENV=development-Bypass (mirrors gdpr-export's _get_uid): ein
    Firebase-ID-Token lässt sich unabhängig vom Backend-Ziel verifizieren,
    daher verhält sich der lokale Dienst exakt wie die Produktion – lokale
    Uploads landen unter der echten uid des angemeldeten Nutzers, nicht
    unter einer Platzhalter-uid."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization-Token fehlt")

    token = authorization.removeprefix("Bearer ")
    try:
        decoded = fb_auth.verify_id_token(token, app=_get_firebase_app())
        return decoded["uid"]
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Ungültiger Token") from exc


def assert_owns_path(uid: str, object_path: str) -> None:
    """Wirft 403, wenn object_path nicht unter dem eigenen users/{uid}/-Präfix
    liegt. Muss vor JEDER Storage-Mutation (delete) aufgerufen werden, damit
    kein Nutzer auf die Objekte eines anderen Nutzers zugreifen kann."""
    if not object_path.startswith(f"users/{uid}/"):
        raise HTTPException(status_code=403, detail="Kein Zugriff auf dieses Objekt")
