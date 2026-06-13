import logging
import os
import queue
import tempfile
import threading
import traceback

import cv2
import numpy as np

# Silence tqdm progress bars BEFORE feat is imported (env var is read at tqdm import time)
os.environ.setdefault("TQDM_DISABLE", "1")


class PainDetector:
    """
    py-feat pretrained AU detector → PSPI → pain probability 0-100%.

    Runs in a background daemon thread so the camera loop is never blocked.
    The first PAIN_BASELINE_FRAMES successful detections calibrate the subject's
    neutral PSPI so the output measures change-from-normal, not absolute geometry.

    PSPI = AU04 + max(AU06, AU07) + max(AU09, AU10) + AU43   (clinical range 0-16)
    """

    _PSPI_CORE = ["AU04", "AU06", "AU07", "AU09", "AU10", "AU43"]
    _PSPI_MAX  = 5.0   # practical normalization ceiling for acted pain (PSPI delta ~2-5)

    def __init__(self, baseline_frames: int = 90):
        self._baseline_target = baseline_frames
        self._baseline_buffer = []
        self._baseline        = None
        self._latest_prob     = None
        self._lock  = threading.Lock()
        self._queue = queue.Queue(maxsize=2)
        self._stop  = threading.Event()
        self._detector = None

        # Silence feat's verbose logging (safer than redirecting sys.stderr in a thread)
        for name in ("feat", "feat.detector", "feat.pretrained_models", "root"):
            logging.getLogger(name).setLevel(logging.CRITICAL)

        try:
            from feat import Detector
            self._detector = Detector(au_model="xgb")
            print("✅ py-feat pain detector loaded.")
        except Exception as e:
            print(f"⚠  py-feat not available ({e}). Run: pip install py-feat")
            return

        self._thread = threading.Thread(target=self._worker, daemon=True)
        self._thread.start()
        print("[PainDetector] Background worker started.")

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def predict(self, frame: np.ndarray) -> "float | None":
        """Push frame to the background thread; return latest cached result. Never blocks."""
        if self._detector is None:
            return None
        try:
            self._queue.put_nowait(frame.copy())
        except queue.Full:
            pass
        with self._lock:
            return self._latest_prob

    @property
    def calibrating(self) -> bool:
        if self._detector is None:
            return False
        with self._lock:
            return self._baseline is None

    @property
    def calibration_count(self) -> int:
        with self._lock:
            return len(self._baseline_buffer)

    def close(self):
        self._stop.set()
        if hasattr(self, "_thread"):
            self._thread.join(timeout=2)

    # ------------------------------------------------------------------
    # Background worker
    # ------------------------------------------------------------------

    def _worker(self):
        frames_tried = 0
        while not self._stop.is_set():
            try:
                frame = self._queue.get(timeout=0.5)
            except queue.Empty:
                continue

            frames_tried += 1
            try:
                pspi = self._compute_pspi(frame)
                if pspi is None:
                    print(f"[PainDetector] Frame {frames_tried}: no face detected — ensure face is visible")
                    continue

                with self._lock:
                    if self._baseline is None:
                        self._baseline_buffer.append(pspi)
                        n = len(self._baseline_buffer)
                        print(f"[PainDetector] Calibrating {n}/{self._baseline_target}, PSPI={pspi:.2f}")
                        if n >= self._baseline_target:
                            self._baseline = float(np.mean(self._baseline_buffer))
                            print(f"[PainDetector] ✅ Baseline set: PSPI={self._baseline:.2f}")
                    else:
                        prob = max(0.0, pspi - self._baseline) / self._PSPI_MAX * 100.0
                        self._latest_prob = float(np.clip(prob, 0.0, 100.0))
            except Exception:
                print(f"[PainDetector] Error in worker (frame {frames_tried}):")
                traceback.print_exc()

    # ------------------------------------------------------------------
    # AU detection
    # ------------------------------------------------------------------

    def _compute_pspi(self, frame: np.ndarray) -> "float | None":
        """Write frame to a temp JPEG, run py-feat, return raw PSPI (0-16) or None."""
        tmp_fd, tmp_path = tempfile.mkstemp(suffix=".jpg")
        os.close(tmp_fd)
        try:
            ok = cv2.imwrite(tmp_path, frame)
            if not ok:
                print("[PainDetector] cv2.imwrite failed — skipping frame")
                return None
            result = self._detector.detect_image(tmp_path)
        finally:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

        if result is None or (hasattr(result, "empty") and result.empty):
            return None

        aus = {}
        for col in self._PSPI_CORE:
            if col not in result.columns:
                aus[col] = 0.0
                continue
            val = result[col].iloc[0]
            if val != val:  # NaN → no face
                return None
            aus[col] = max(0.0, float(val))

        # AU12 (lip corner puller) is the smile indicator — NaN-safe
        au12 = 0.0
        if "AU12" in result.columns:
            v = result["AU12"].iloc[0]
            if v == v:
                au12 = max(0.0, float(v))

        # AU04 (brow lowering) weighted 2× — primary pain anchor, absent in smiles
        pspi = (
            2.0 * aus["AU04"]
            + max(aus["AU06"], aus["AU07"])
            + max(aus["AU09"], aus["AU10"])
            + aus["AU43"]
        )

        # Smile inhibitor: high AU12 suppresses pain score
        pspi *= max(0.0, 1.0 - au12 / 3.0)

        return float(np.clip(pspi, 0.0, 20.0))
