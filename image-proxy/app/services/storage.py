from firebase_admin import storage

from app.services.auth import _get_firebase_app

# Explizit benannt statt storage.bucket() ohne Argument – vermeidet jede
# Mehrdeutigkeit über die "Default Bucket"-Auflösung des Firebase-Projekts.
_BUCKET_NAME = "diary-6fa61.firebasestorage.app"


def get_bucket():
    _get_firebase_app()
    return storage.bucket(_BUCKET_NAME)
