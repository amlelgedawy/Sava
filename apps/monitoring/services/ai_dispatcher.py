"""
AIDispatcher

Sends JPEG frames to the AI microservices in background threads.
Results are POSTed back to Django's /api/stream/ai-result endpoint
so the response can be processed by ResultProcessor in the normal
request cycle.
"""

import threading
import time
import requests
from django.conf import settings


def _callback_url(port: int) -> str:
    host = getattr(settings, "DJANGO_HOST", "127.0.0.1")
    return f"http://{host}:{port}/api/stream/ai-result"

# How often (seconds) to send a frame to the Activity Server per patient
ACTIVITY_RECOGNITION_INTERVAL = 1.0

# How often (seconds) to send a frame to the face AI server per patient
FACE_RECOGNITION_INTERVAL = 5.0

_last_activity_check: dict[str, float] = {}
_activity_lock = threading.Lock()

_last_face_check: dict[str, float] = {}
_face_lock = threading.Lock()


def dispatch(patient_id: str, jpeg_bytes: bytes, django_port: int = 8000) -> None:
    """
    Fire-and-forget dispatcher called by the push-frame endpoint.

    Spawns background threads to:
      1. Send frame to Activity Server (every ACTIVITY_RECOGNITION_INTERVAL seconds)
      2. Send frame to Face AI Server  (every FACE_RECOGNITION_INTERVAL seconds)

    Each thread POSTs the AI result back to Django's ai-result endpoint.
    """
    callback = _callback_url(django_port)
    now = time.time()

    with _activity_lock:
        last = _last_activity_check.get(patient_id, 0)
        activity_due = (now - last) >= ACTIVITY_RECOGNITION_INTERVAL
        if activity_due:
            _last_activity_check[patient_id] = now

    if activity_due:
        threading.Thread(
            target=_call_activity_server,
            args=(patient_id, jpeg_bytes, callback),
            daemon=True,
        ).start()

    with _face_lock:
        last = _last_face_check.get(patient_id, 0)
        due = (now - last) >= FACE_RECOGNITION_INTERVAL
        if due:
            _last_face_check[patient_id] = now

    if due:
        threading.Thread(
            target=_call_face_server,
            args=(patient_id, jpeg_bytes, callback),
            daemon=True,
        ).start()


def _call_activity_server(patient_id: str, jpeg_bytes: bytes, callback: str) -> None:
    """POST frame to Activity Server, forward result to Django."""
    url = settings.ACTIVITY_SERVER_URL.rstrip("/") + "/process-frame"
    try:
        resp = requests.post(
            url,
            files={"frame": ("frame.jpg", jpeg_bytes, "image/jpeg")},
            data={"patient_id": patient_id},
            timeout=15,
        )
        if resp.status_code == 200:
            _post_result(callback, {
                "source": "ACTIVITY_SERVER",
                "patient_id": patient_id,
                "result": resp.json(),
            })
    except Exception as e:
        print(f"[AIDispatcher] Activity server error: {e}")


def _call_face_server(patient_id: str, jpeg_bytes: bytes, callback: str) -> None:
    """POST frame to Face AI Server, forward result to Django."""
    url = settings.AI_SERVER_URL.rstrip("/") + settings.AI_FACE_ENDPOINT
    try:
        resp = requests.post(
            url,
            files={"frame": ("frame.jpg", jpeg_bytes, "image/jpeg")},
            data={"patient_id": patient_id},
            timeout=10,
        )
        if resp.status_code == 200:
            _post_result(callback, {
                "source": "FACE_SERVER",
                "patient_id": patient_id,
                "result": resp.json(),
            })
    except Exception as e:
        print(f"[AIDispatcher] Face server error: {e}")


def _post_result(callback: str, payload: dict) -> None:
    """POST AI result back to Django's ai-result endpoint."""
    try:
        requests.post(callback, json=payload, timeout=10)
    except Exception as e:
        print(f"[AIDispatcher] Callback error: {e}")
