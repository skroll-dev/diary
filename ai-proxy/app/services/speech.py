"""
Google Cloud Speech-to-Text v2 (Chirp)
Region: europe-west3 (Frankfurt)
"""
import os
from google.cloud.speech_v2 import SpeechAsyncClient
from google.cloud.speech_v2.types import cloud_speech

GCP_PROJECT = os.environ["GCP_PROJECT"]
RECOGNIZER = f"projects/{GCP_PROJECT}/locations/europe-west3/recognizers/_"


async def transcribe_audio(audio_bytes: bytes, content_type: str) -> dict:
    client = SpeechAsyncClient()

    audio_encoding = (
        cloud_speech.RecognitionConfig.AudioEncoding.MP3
        if "mpeg" in content_type or "m4a" in content_type
        else cloud_speech.RecognitionConfig.AudioEncoding.LINEAR16
    )

    config = cloud_speech.RecognitionConfig(
        auto_decoding_config=cloud_speech.AutoDetectDecodingConfig(),
        language_codes=["de-DE"],
        model="chirp",
    )

    request = cloud_speech.RecognizeRequest(
        recognizer=RECOGNIZER,
        config=config,
        content=audio_bytes,
    )

    response = await client.recognize(request=request)

    transcript_parts = []
    total_duration = 0.0

    for result in response.results:
        alt = result.alternatives[0]
        transcript_parts.append(alt.transcript)
        if result.result_end_offset:
            total_duration = result.result_end_offset.total_seconds()

    return {
        "transcript": " ".join(transcript_parts).strip(),
        "duration_seconds": total_duration,
        "language_detected": "de",
    }
