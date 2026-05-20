"""
StreamManager
-------------
Holds the latest JPEG frame per patient in memory.
Provides an MJPEG frame generator for Django streaming responses.

All state is process-local (RAM only) — no database involvement.
"""

import threading
import time

_lock = threading.Lock()
_buffers: dict[str, bytes] = {}   # patient_id -> latest JPEG bytes
_timestamps: dict[str, float] = {}  # patient_id -> epoch of last push
_detections: dict[str, dict] = {}  # patient_id -> {source: {result, timestamp}}

FRAME_STALE_SECONDS = 30          # treat frame as gone after this many seconds
DETECTION_STALE_SECONDS = 10       # treat detection as gone after this


class StreamManager:

    @staticmethod
    def push_frame(patient_id: str, jpeg_bytes: bytes) -> None:
        """Store the latest frame for a patient. Called by the push-frame endpoint."""
        with _lock:
            _buffers[patient_id] = jpeg_bytes
            _timestamps[patient_id] = time.time()

    @staticmethod
    def get_latest_frame(patient_id: str) -> bytes | None:
        """Return the most recent JPEG bytes for a patient, or None if stale/absent."""
        with _lock:
            last_ts = _timestamps.get(patient_id, 0)
            if time.time() - last_ts > FRAME_STALE_SECONDS:
                return None
            return _buffers.get(patient_id)

    @staticmethod
    def mjpeg_generator(patient_id: str, fps: int = 10):
        """
        Generator that yields MJPEG multipart chunks.
        Blocks between frames to honour the requested fps.

        """
        interval = 1.0 / max(fps, 1)
        _PLACEHOLDER = _make_placeholder()

        while True:
            frame = StreamManager.get_latest_frame(patient_id) or _PLACEHOLDER
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n\r\n"
                + frame
                + b"\r\n"
            )
            time.sleep(interval)

    @staticmethod
    def set_detection(patient_id: str, source: str, result: dict) -> None:
        """Store latest AI result for a patient/source pair."""
        with _lock:
            patient_dets = _detections.setdefault(patient_id, {})
            patient_dets[source] = {"result": result, "timestamp": time.time()}

    @staticmethod
    def get_detections(patient_id: str) -> dict:
        """Return all non-stale detections for a patient as {source: result}."""
        now = time.time()
        out = {}
        with _lock:
            patient_dets = _detections.get(patient_id, {})
            for source, entry in patient_dets.items():
                if now - entry["timestamp"] <= DETECTION_STALE_SECONDS:
                    out[source] = entry["result"]
        return out

    @staticmethod
    def active_patients() -> list[str]:
        """Return patient_ids that have a non-stale frame."""
        now = time.time()
        with _lock:
            return [
                pid for pid, ts in _timestamps.items()
                if now - ts <= FRAME_STALE_SECONDS
            ]


def _make_placeholder() -> bytes:
    """1×1 grey JPEG used when no real frame is available yet."""
    try:
        import numpy as np
        import cv2
        img = np.full((240, 320, 3), 128, dtype="uint8")
        _, buf = cv2.imencode(".jpg", img)
        return buf.tobytes()
    except Exception:
        return b""
