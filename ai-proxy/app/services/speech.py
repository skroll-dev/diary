"""
Google Cloud Speech-to-Text v2 — Chirp 3
Multi-region: eu (eu-speech.googleapis.com)
"""
import os
from google.api_core.client_options import ClientOptions
from google.cloud.speech_v2 import SpeechAsyncClient
from google.cloud.speech_v2.types import cloud_speech

GCP_PROJECT = os.environ["GCP_PROJECT"]
RECOGNIZER = f"projects/{GCP_PROJECT}/locations/eu/recognizers/_"


async def transcribe_audio(audio_bytes: bytes) -> dict:
    client = SpeechAsyncClient(
        client_options=ClientOptions(api_endpoint="eu-speech.googleapis.com")
    )

    config = cloud_speech.RecognitionConfig(
        auto_decoding_config=cloud_speech.AutoDetectDecodingConfig(),
        language_codes=["de-DE"],
        model="chirp_3",
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
