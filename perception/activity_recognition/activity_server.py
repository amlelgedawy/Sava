"""
SAVA Activity Recognition Server
Receives JPEG frames from the Flutter app or Raspberry Pi camera and runs the
full activity recognition pipeline:
  - YOLO person detection
  - MediaPipe pose estimation (64-frame sliding window per session)
  - SkateFormer 9-class activity recognition (with temporal smoothing)
  - Wandering detection
  - Dangerous object detection
  - Returns all results as JSON — Django's AIDispatcher handles event storage and alerting

Run with:
    .\venv310\Scripts\python -m perception.activity_recognition.activity_server

Endpoints:
  POST /process-frame    multipart "frame" (JPEG) + form field "patient_id"
                         Returns activity prediction, wandering flag, dangerous
                         objects, person bbox.
  GET  /health           Server status + model info.
  POST /reset-session    Reset state for a patient (clears pose buffer, etc.)
"""

import io
import os
import sys
import time
import threading
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch
from flask import Flask, request, jsonify
from flask_cors import CORS
from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))

# Reuse existing pipeline components
from pose_estimator import PoseEstimator
from camera import (
    CLASS_NAMES,
    _load_model,
    _predict,
    WanderingDetector,
)
from object_detector import DangerousObjectDetector
from config import TARGET_FPS

# ── Configuration ─────────────────────────────────────────────────────────────
PORT = int(os.environ.get("ACTIVITY_SERVER_PORT", "5003"))

# Temporal smoothing (same as camera.py)
SMOOTH_WINDOW = 15
CONFIDENCE_THRESH = 0.60
CLASS_THRESHOLDS = {"FALL": 0.75, "CHEST_PAIN": 0.75}
FALL_PERSIST_FRAMES = 10

# ── App init ──────────────────────────────────────────────────────────────────
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"[ActivityServer] Device: {device}")

# Cap CPU threads per inference call — this process shares the machine with
# Django and the emulator, and unbounded thread pools make every call grab
# all available cores.
cv2.setNumThreads(2)
torch.set_num_threads(2)

# Load shared models once at startup
print("[ActivityServer] Loading YOLO person detector...")
from ultralytics import YOLO
# Use yolov8n.pt - will auto-download from Ultralytics if not present
yolo = YOLO("yolov8n.pt")
# Warm up now (single-threaded) so YOLO's lazy fuse() runs here, not
# racing across waitress's worker threads on the first real request.
yolo(np.zeros((640, 640, 3), dtype=np.uint8), classes=[0], verbose=False)

print("[ActivityServer] Loading SkateFormer activity model...")
skateformer_model = _load_model(device)

print("[ActivityServer] Loading dangerous object detector...")
obj_detector = DangerousObjectDetector()
obj_loaded = obj_detector.load()
if obj_loaded:
    obj_detector.detect(np.zeros((640, 640, 3), dtype=np.uint8))
else:
    print("[ActivityServer]   Object detection disabled — model not found.")


# ── Per-session state ─────────────────────────────────────────────────────────
class Session:
    """Holds per-patient pipeline state (pose buffer, smoothing buffer, wandering)."""

    def __init__(self):
        self.pose_est = PoseEstimator()
        self.probs_buffer = deque(maxlen=SMOOTH_WINDOW)
        self.wandering = WanderingDetector()
        self.last_pred = None
        self.last_conf = 0.0
        self.fall_consec = 0
        self.last_used = time.time()

    def close(self):
        try:
            self.pose_est.close()
        except Exception:
            pass


_sessions = {}
_sessions_lock = threading.Lock()
SESSION_TTL_SECONDS = 300  # 5 min of inactivity → drop session


def _get_session(patient_id):
    """Return (and lazily create) a Session for the given patient_id."""
    key = patient_id or "_default"
    with _sessions_lock:
        sess = _sessions.get(key)
        if sess is None:
            sess = Session()
            _sessions[key] = sess
            print(f"[ActivityServer] New session for patient_id={key}")
        sess.last_used = time.time()
        return sess


def _gc_sessions():
    """Background thread: drop stale sessions to free memory."""
    while True:
        time.sleep(60)
        now = time.time()
        with _sessions_lock:
            stale = [k for k, s in _sessions.items() if now - s.last_used > SESSION_TTL_SECONDS]
            for k in stale:
                _sessions[k].close()
                del _sessions[k]
                print(f"[ActivityServer] Dropped stale session: {k}")


threading.Thread(target=_gc_sessions, daemon=True).start()


# ── Frame processing ──────────────────────────────────────────────────────────

def _decode_frame(frame_bytes):
    """JPEG bytes → BGR ndarray (OpenCV format)."""
    image = Image.open(io.BytesIO(frame_bytes))
    image = ImageOps.exif_transpose(image).convert("RGB")
    rgb = np.array(image)
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)


def _detect_person(frame):
    """Run YOLO person detection. Returns (bbox_center, boxes_list_normalized)."""
    results = yolo(frame, classes=[0], verbose=False)
    boxes = results[0].boxes
    h, w = frame.shape[:2]

    center = None
    person_boxes = []
    if boxes is not None and len(boxes) > 0:
        # Highest-confidence person box for tracking centre
        best = boxes[boxes.conf.argmax()]
        x1, y1, x2, y2 = best.xyxy[0].cpu().numpy()
        center = (int((x1 + x2) / 2), int((y1 + y2) / 2))

        # Return all person boxes (normalized) for the client to draw
        for box in boxes:
            bx1, by1, bx2, by2 = box.xyxy[0].cpu().numpy()
            person_boxes.append({
                "x1": round(float(bx1) / w, 4),
                "y1": round(float(by1) / h, 4),
                "x2": round(float(bx2) / w, 4),
                "y2": round(float(by2) / h, 4),
                "confidence": round(float(box.conf[0]), 3),
            })

    return center, person_boxes


@app.route("/process-frame", methods=["POST"])
def process_frame():
    if "frame" not in request.files:
        return jsonify({"error": "No frame provided"}), 400

    patient_id = request.form.get("patient_id") or None
    sess = _get_session(patient_id)

    try:
        frame_bytes = request.files["frame"].read()
        frame = _decode_frame(frame_bytes)
        h, w = frame.shape[:2]

        # 1) Person detection
        bbox_center, person_boxes = _detect_person(frame)

        # 2) Pose estimation → fills 64-frame buffer (no drawing — Flutter renders overlays)
        _, kps = sess.pose_est.extract(frame, draw=False)
        pose_detected = kps is not None

        # 3) Activity recognition (SkateFormer)
        activity = None
        confidence = 0.0
        buffer_progress = 0
        if skateformer_model is not None:
            sk_input = sess.pose_est.get_skateformer_input()
            if sk_input is not None:
                probs = _predict(skateformer_model, device, sk_input)
                sess.probs_buffer.append(probs)
                avg_probs = np.mean(sess.probs_buffer, axis=0)
                best_id = int(np.argmax(avg_probs))
                best_conf = float(avg_probs[best_id])
                pred_name = CLASS_NAMES[best_id]
                threshold = CLASS_THRESHOLDS.get(pred_name, CONFIDENCE_THRESH)
                if best_conf >= threshold:
                    sess.last_pred = pred_name
                    sess.last_conf = best_conf
                    activity = pred_name
                    confidence = best_conf
                else:
                    sess.last_pred = None
                    sess.last_conf = best_conf
                    confidence = best_conf
            buffer_progress = min(len(sess.pose_est._buffer), 64)

        # 4) FALL persistence
        if sess.last_pred == "FALL":
            sess.fall_consec += 1
        else:
            sess.fall_consec = 0
        fall_alert = sess.fall_consec >= FALL_PERSIST_FRAMES

        # 5) Wandering
        sess.wandering.update(sess.last_pred or "", bbox_center)
        is_wandering = sess.wandering.is_wandering

        # 6) Dangerous objects
        obj_dets = obj_detector.detect(frame) if obj_loaded else []
        dangerous_objects = [
            {
                "label": d["label"],
                "confidence": d["confidence"],
                "danger_level": d["danger_level"],
                "box": d["box_norm"],
            }
            for d in obj_dets
        ]

        return jsonify({
            "activity": activity,
            "confidence": round(confidence, 3),
            "fall_alert": fall_alert,
            "wandering": is_wandering,
            "pose_detected": pose_detected,
            "buffer_progress": buffer_progress,
            "buffer_target": 64,
            "person_boxes": person_boxes,
            "dangerous_objects": dangerous_objects,
            "frame_size": {"w": w, "h": h},
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/reset-session", methods=["POST"])
def reset_session():
    patient_id = request.form.get("patient_id") or request.json.get("patient_id") if request.is_json else request.form.get("patient_id")
    key = patient_id or "_default"
    with _sessions_lock:
        sess = _sessions.pop(key, None)
        if sess:
            sess.close()
    return jsonify({"reset": True, "patient_id": key})


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "device": device,
        "skateformer_loaded": skateformer_model is not None,
        "object_detection_loaded": obj_loaded,
        "active_sessions": len(_sessions),
        "classes": CLASS_NAMES,
    })


if __name__ == "__main__":
    print(f"[ActivityServer] Listening on http://0.0.0.0:{PORT}")
    # Use waitress on Windows — Flask's dev server hits a click/_winconsole
    # OSError when printing its banner inside certain venv/console combos.
    try:
        from waitress import serve
        serve(app, host="0.0.0.0", port=PORT, threads=8)
    except ImportError:
        print("[ActivityServer] waitress not installed — falling back to Flask dev server.")
        print("[ActivityServer] Install with:  pip install waitress")
        app.run(host="0.0.0.0", port=PORT, debug=False, threaded=True)
