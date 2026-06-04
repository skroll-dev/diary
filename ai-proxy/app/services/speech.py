"""
Google Cloud Speech-to-Text v2 — Chirp 3
Multi-region: eu (eu-speech.googleapis.com)
"""
import asyncio
import os
import structlog
from collections.abc import Callable, Coroutine
from google.api_core.client_options import ClientOptions
from google.cloud.speech_v2 import SpeechAsyncClient
from google.cloud.speech_v2.types import cloud_speech

log = structlog.get_logger()

GCP_PROJECT = os.environ["GCP_PROJECT"]
RECOGNIZER = f"projects/{GCP_PROJECT}/locations/eu/recognizers/_"


def _denoiser(enabled: bool) -> cloud_speech.DenoiserConfig | None:
    if not enabled:
        return None
    return cloud_speech.DenoiserConfig(
        denoise_audio=True,
        snr_threshold=0.0,  # deprecated in Chirp 3; 0.0 for compatibility
    )


async def transcribe_audio(audio_bytes: bytes, *, denoise_audio: bool = True) -> dict:
    client = SpeechAsyncClient(
        client_options=ClientOptions(api_endpoint="eu-speech.googleapis.com")
    )

    config = cloud_speech.RecognitionConfig(
        auto_decoding_config=cloud_speech.AutoDetectDecodingConfig(),
        language_codes=["de-DE"],
        model="chirp_3",
        denoiser_config=_denoiser(denoise_audio),
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


async def stream_transcribe_audio(
    audio_queue: asyncio.Queue,
    on_interim: Callable[[str], Coroutine] | None = None,
    on_segment: Callable[[str], Coroutine] | None = None,
    *,
    denoise_audio: bool = True,
    sample_rate: int = 44100,
) -> dict:
    """StreamingRecognize path for the WebSocket endpoint.

    Feeds PCM16 chunks from *audio_queue* to Chirp 3 in real time.
    Calls *on_interim* for each is_final=False result and *on_segment* for
    each is_final=True result; returns the full joined transcript when done.
    """
    client = SpeechAsyncClient(
        client_options=ClientOptions(api_endpoint="eu-speech.googleapis.com")
    )
    streaming_config = cloud_speech.StreamingRecognitionConfig(
        config=cloud_speech.RecognitionConfig(
            explicit_decoding_config=cloud_speech.ExplicitDecodingConfig(
                encoding=cloud_speech.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
                sample_rate_hertz=sample_rate,
                audio_channel_count=1,
            ),
            language_codes=["de-DE"],
            model="chirp_3",
            denoiser_config=_denoiser(denoise_audio),
        ),
        streaming_features=cloud_speech.StreamingRecognitionFeatures(
            interim_results=True,
        ),
    )

    chunks_sent = 0
    audio_stream_done = False  # set to True once the client closes the stream

    # Chirp 3 streaming rejects chunks larger than 25600 bytes.
    _MAX_CHUNK = 25600

    async def _requests():
        nonlocal chunks_sent, audio_stream_done
        yield cloud_speech.StreamingRecognizeRequest(
            recognizer=RECOGNIZER, streaming_config=streaming_config
        )
        while True:
            chunk = await audio_queue.get()
            if chunk is None:
                audio_stream_done = True
                log.debug("stream_requests_done", chunks_sent=chunks_sent)
                return
            for offset in range(0, len(chunk), _MAX_CHUNK):
                chunks_sent += 1
                yield cloud_speech.StreamingRecognizeRequest(audio=chunk[offset:offset + _MAX_CHUNK])

    final_parts: list[str] = []
    total_duration = 0.0
    response_count = 0
    last_interim: str = ""  # last interim text since the most recent final

    log.debug("stream_recognize_start")
    async for response in await client.streaming_recognize(requests=_requests()):
        response_count += 1
        for result in response.results:
            finish = result.alternatives[0].transcript if result.alternatives else ""
            log.debug(
                "stream_result",
                is_final=result.is_final,
                text=finish[:60],
                response_n=response_count,
                post_stream=audio_stream_done,
            )
            if not result.alternatives:
                continue
            text = result.alternatives[0].transcript
            if result.is_final:
                final_parts.append(text)
                last_interim = ""  # this segment is now finalized
                if result.result_end_offset:
                    total_duration = result.result_end_offset.total_seconds()
                if on_segment and text:
                    await on_segment(text)
            elif text:
                last_interim = text
                if on_interim:
                    await on_interim(text)

    # Chirp 3 sometimes never emits is_final=True for the last segment — include
    # whatever interim was in flight when the response stream closed.
    if last_interim:
        log.warning("stream_unfinalized_interim_included", text=last_interim[:80])
        final_parts.append(last_interim)

    log.debug("stream_recognize_done", responses=response_count, finals=len(final_parts))
    return {
        "transcript": " ".join(final_parts).strip(),
        "duration_seconds": total_duration,
        "language_detected": "de",
    }
