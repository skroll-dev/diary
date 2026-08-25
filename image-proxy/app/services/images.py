"""Bildverarbeitung: Resizing, EXIF-Entfernung, Objekt-Pfad-Konstruktion."""
import io
import re
import time
from uuid import uuid4

from PIL import Image, ImageOps

import pillow_heif

pillow_heif.register_heif_opener()

# Muss mit kMaxImagesPerEntry in
# flutter/lib/shared/constants/image_limits.dart synchron bleiben.
MAX_IMAGES_PER_ENTRY = 10

FULL_MAX_DIMENSION = 2048
THUMB_MAX_DIMENSION = 320
JPEG_QUALITY = 85

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

ALLOWED_CONTENT_TYPES = {
    "image/jpeg",
    "image/png",
    "image/heic",
    "image/heif",
    "image/webp",
}

MAX_UPLOAD_BYTES = 15 * 1024 * 1024


def is_valid_date(date: str) -> bool:
    return bool(_DATE_RE.match(date))


def process_upload(raw: bytes) -> tuple[bytes, bytes, tuple[int, int], tuple[int, int]]:
    """Dekodiert raw, richtet die EXIF-Rotation aus, entfernt sämtliche
    Metadaten (nicht nur GPS – da ohnehin komplett neu kodiert wird, ist ein
    vollständiger Verzicht auf `exif=` einfacher und strikt sicherer als eine
    selektive Filterung) und liefert (full_jpeg, thumb_jpeg, full_size, thumb_size).
    """
    img = Image.open(io.BytesIO(raw))
    # WICHTIG: exif_transpose() MUSS vor jeder weiteren Verarbeitung passieren –
    # Pillow rotiert beim Öffnen nicht automatisch. Ohne diesen Schritt würden
    # Hochkant-Fotos nach dem EXIF-Strip seitlich verdreht dargestellt.
    img = ImageOps.exif_transpose(img)
    img = img.convert("RGB")

    full = img.copy()
    full.thumbnail((FULL_MAX_DIMENSION, FULL_MAX_DIMENSION), Image.LANCZOS)
    thumb = img.copy()
    thumb.thumbnail((THUMB_MAX_DIMENSION, THUMB_MAX_DIMENSION), Image.LANCZOS)

    def _encode(im: Image.Image) -> bytes:
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=JPEG_QUALITY, optimize=True)
        return buf.getvalue()

    return _encode(full), _encode(thumb), full.size, thumb.size


def build_object_paths(*, uid: str, date: str, entry_ordinal: int, upload_token: str) -> tuple[str, str]:
    """Rein & deterministisch für die gegebenen Eingaben. Layout:
    users/{uid}/{date}_entry{entry_ordinal}/{upload_token}_full.jpg
    users/{uid}/{date}_entry{entry_ordinal}/{upload_token}_thumb.jpg

    entry_ordinal ist rein kosmetisch (menschlich browsbarer Ordnername in der
    GCS-Konsole) – niemals zur Pfad-Rekonstruktion verwenden, Pfade werden
    beim Upload einmalig erzeugt und danach unverändert gespeichert.
    """
    prefix = f"users/{uid}/{date}_entry{entry_ordinal}"
    return f"{prefix}/{upload_token}_full.jpg", f"{prefix}/{upload_token}_thumb.jpg"


def new_upload_token() -> str:
    # Kollisionssicher ohne list_blobs-Lookup, sortiert chronologisch in der
    # GCS-Konsole. Treibt NICHT die sortierbare `order`-Anzeige (das ist ein
    # eigenes, veränderliches DB-Feld) – ein Umbenennen von Storage-Objekten
    # bei jedem Reorder wäre unnötiges Copy+Delete.
    return f"{int(time.time())}_{uuid4().hex[:6]}"
