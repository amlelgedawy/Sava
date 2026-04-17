import sys
import time
import threading
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch
import requests

from .config import (
    CAMERA_INDEX, FRAME_WIDTH, FRAME_HEIGHT,
    TARGET_FPS, ENABLE_RECORDING, OUTPUT_VIDEO_NAME,
    WANDERING_TORTUOSITY_THRESHOLD, WANDERING_BUFFER_FRAMES,
    WANDERING_MIN_WALK_SECONDS,
)
from .detector import detect_person
from .pose_estimator import PoseEstimator

# ----------------------------
# SkateFormer paths & config
# ----------------------x------
import os
SKATEFORMER_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "SkateFormer", "SkateFormer-main")
CHECKPOINT      = Path(os.path.join(os.path.dirname(__file__), "work_dir", "sava_9class", "best_9class.pt"))
CLASS_NAMES     = ["EAT", "DRINK", "SLEEP", "FALL", "WALK", "SIT", "STAND", "USE_PHONE", "CHEST_PAIN"]

# Overlay colours per label
LABEL_COLORS = {
    "EAT":        (0, 200, 255),  # yellow
    "DRINK":      (0, 200, 255),  # yellow
    "SLEEP":      (200, 200, 0),  # cyan
    "FALL":       (0, 0, 255),    # red — alert
    "WALK":       (0, 255, 0),    # green
    "SIT":        (255, 180, 0),  # orange
    "STAND":      (255, 255, 0),  # light blue
    "USE_PHONE":  (180, 0, 255),  # purple
    "CHEST_PAIN": (0, 0, 255),    # red — alert
}


# ---------------------------------------------------------------------------
# Model loading & inference
# ---------------------------------------------------------------------------

def _load_model(device):
    """Load fine-tuned 9-class SkateFormer. Returns model or None if checkpoint missing."""
    if not CHECKPOINT.exists():
        print(f"  Checkpoint not found: {CHECKPOINT}")
        print("   Run train_finetune_v2.py first. Running without activity recognition.")
        return None

    if SKATEFORMER_DIR not in sys.path:
        sys.path.insert(0, SKATEFORMER_DIR)

    try:
        from model.SkateFormer import SkateFormer
    except ImportError:
        print("  SkateFormer model not found. Running without activity recognition.")
        return None

    model = SkateFormer(
        in_channels=3,
        depths=(2, 2, 2, 2),
        channels=(96, 192, 192, 192),
        num_classes=len(CLASS_NAMES),   # 9
        embed_dim=96,
        num_people=2,
        num_frames=64,
        num_points=24,
        kernel_size=7,
        num_heads=32,
        type_1_size=(8, 8),
        type_2_size=(8, 12),
        type_3_size=(8, 8),
        type_4_size=(8, 12),
        attn_drop=0.5,
        head_drop=0.0,
        rel=True,
        drop_path=0.2,
        mlp_ratio=4.0,
        index_t=True
    ).to(device)

    ckpt = torch.load(str(CHECKPOINT), map_location=device)
    model.load_state_dict(ckpt["model"], strict=True)
    model.eval()
    print(f" Loaded 9-class SkateFormer from {CHECKPOINT}")
    return model


@torch.no_grad()
def _predict(model, device, skateformer_input):
    """
    skateformer_input: ndarray (3, 64, 24, 2)
    Returns softmax probability vector (9,) as ndarray.
    """
    x       = torch.from_numpy(skateformer_input).float().unsqueeze(0).to(device)
    index_t = torch.arange(64, dtype=torch.long).unsqueeze(0).to(device)
    logits  = model(x, index_t)
    probs   = torch.softmax(logits, dim=1)[0].cpu().numpy()
    return probs


# ---------------------------------------------------------------------------
# Wandering Detector
# ---------------------------------------------------------------------------

class WanderingDetector:
    """
    Tracks the person's position over time and detects aimless wandering.

    Algorithm:
      - Maintains a sliding window of YOLO bbox centres (up to 5 min @ 15 fps)
      - When SkateFormer says WALK, accumulates walking duration
      - Every second computes tortuosity = total_path / net_displacement
      - Flags WANDERING when:
          walking duration > WANDERING_MIN_WALK_SECONDS  AND
          tortuosity       > WANDERING_TORTUOSITY_THRESHOLD
    """

    def __init__(self):
        self._positions   = deque(maxlen=WANDERING_BUFFER_FRAMES)
        self._walk_frames = 0          # consecutive frames labelled WALK
        self._wandering   = False

    def update(self, label, bbox_center):
        """
        Call once per frame.
        label       : str — current SkateFormer prediction
        bbox_center : (cx, cy) in pixels from YOLO, or None if no person detected
        """
        if label == "WALK" and bbox_center is not None:
            self._positions.append(bbox_center)
            self._walk_frames += 1
        else:
            # Reset when patient stops walking
            self._walk_frames = 0
            self._wandering   = False
            return

        walk_seconds = self._walk_frames / TARGET_FPS

        # Only evaluate after minimum walk duration
        if walk_seconds < WANDERING_MIN_WALK_SECONDS:
            self._wandering = False
            return

        pts = np.array(self._positions, dtype=np.float32)  # (N, 2)
        if len(pts) < 2:
            return

        # Total path length (sum of step distances)
        steps       = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        total_dist  = float(steps.sum())

        # Net displacement (straight-line start → end)
        net_displace = float(np.linalg.norm(pts[-1] - pts[0]))

        tortuosity = total_dist / (net_displace + 1e-6)
        self._wandering = tortuosity > WANDERING_TORTUOSITY_THRESHOLD

    @property
    def is_wandering(self):
        return self._wandering


# ---------------------------------------------------------------------------
# Face Recognition + Person Tracking integration
# ---------------------------------------------------------------------------

DJANGO_API_URL = os.environ.get("DJANGO_API_URL", "http://localhost:8000/api")
AI_FACE_SERVER_URL = os.environ.get("AI_FACE_SERVER_URL", "http://localhost:5000")

# How often to run face recognition (seconds) — not every frame
FACE_RECOGNITION_INTERVAL = 5

# Cooldowns for activity alerts (seconds)
_ALERT_COOLDOWNS = {
    "FALL": 30,
    "CHEST_PAIN": 30,
    "WANDERING": 120,
}
_last_alert_time = {}


class PatientIdentifier:
    """
    Uses the AI face server + Django patient lookup to identify the patient
    in front of the camera. Runs in a background thread so the camera loop
    never blocks on network I/O.
    """

    def __init__(self):
        self.patient_id = None
        self.patient_name = None
        self._last_check = 0
        self._busy = False  # True while a background check is running
        self._name_to_id_cache = {}  # person_name -> patient_id

    def identify(self, frame, yolo_boxes):
        """
        Non-blocking. Immediately returns the cached patient_id.
        Kicks off a background thread every FACE_RECOGNITION_INTERVAL seconds
        to refresh the identity via face recognition.
        """
        now = time.time()
        if self._busy or (now - self._last_check < FACE_RECOGNITION_INTERVAL):
            return self.patient_id
        self._last_check = now

        if yolo_boxes is None or len(yolo_boxes) == 0:
            return self.patient_id

        # Crop the best person detection for face recognition
        best = yolo_boxes[yolo_boxes.conf.argmax()]
        x1, y1, x2, y2 = [int(v) for v in best.xyxy[0].cpu().numpy()]
        h, w = frame.shape[:2]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)
        person_crop = frame[y1:y2, x1:x2]

        if person_crop.size == 0:
            return self.patient_id

        # Encode JPEG on main thread (fast, ~1-2 ms) then send in background
        _, buf = cv2.imencode(".jpg", person_crop)
        jpeg_bytes = buf.tobytes()

        self._busy = True
        threading.Thread(target=self._do_identify, args=(jpeg_bytes,), daemon=True).start()

        return self.patient_id

    def _do_identify(self, jpeg_bytes):
        """Background thread: call AI face server + Django lookup."""
        try:
            resp = requests.post(
                f"{AI_FACE_SERVER_URL}/analyze-face",
                files={"frame": ("face.jpg", jpeg_bytes, "image/jpeg")},
                data={"patient_id": "camera_auto"},
                timeout=5,
            )
            if resp.status_code != 200:
                return

            result = resp.json()
            payload = result.get("payload", {})
            person_name = payload.get("person_name")
            is_known = payload.get("known", False)

            if not is_known or not person_name:
                return

            pid = self._resolve_patient_id(person_name)
            if pid:
                if pid != self.patient_id:
                    print(f" Patient identified: {person_name} (id={pid})")
                self.patient_id = pid
                self.patient_name = person_name

        except Exception:
            pass
        finally:
            self._busy = False

    def _resolve_patient_id(self, person_name):
        """Look up person_name in Django to get the patient_id. Results are cached."""
        if person_name in self._name_to_id_cache:
            return self._name_to_id_cache[person_name]

        try:
            resp = requests.get(
                f"{DJANGO_API_URL}/activity-recognition/patient-lookup",
                params={"name": person_name},
                timeout=5,
            )
            if resp.status_code == 200:
                data = resp.json()
                if data.get("found"):
                    pid = data["patient_id"]
                    self._name_to_id_cache[person_name] = pid
                    return pid
        except Exception:
            pass
        return None


def _send_activity_event(patient_id, activity, confidence, is_wandering=False, walk_duration=0.0):
    """
    POST activity event to Django API in a background thread.
    Respects per-activity cooldowns to avoid flooding.
    """
    if not patient_id:
        return  # No patient identified yet

    now = time.time()
    key = "WANDERING" if is_wandering else activity
    cooldown = _ALERT_COOLDOWNS.get(key, 10)
    if now - _last_alert_time.get(key, 0) < cooldown:
        return  # Still in cooldown
    _last_alert_time[key] = now

    def _post():
        try:
            resp = requests.post(
                f"{DJANGO_API_URL}/activity-recognition/event",
                json={
                    "patient_id": patient_id,
                    "activity": activity,
                    "confidence": float(confidence),
                    "is_wandering": is_wandering,
                    "walk_duration_seconds": float(walk_duration),
                },
                timeout=5,
            )
            if resp.status_code == 201:
                data = resp.json()
                alerts = data.get("alerts_created", 0)
                if alerts > 0:
                    print(f"\U0001f6a8 Alert sent: {activity} -> {alerts} caregiver(s) notified")
            else:
                print(f"\u26a0\ufe0f  Django API error: {resp.status_code}")
        except Exception as e:
            print(f"\u26a0\ufe0f  Could not reach Django API: {e}")

    threading.Thread(target=_post, daemon=True).start()


# ---------------------------------------------------------------------------
# Camera helpers
# ---------------------------------------------------------------------------

def _get_bbox_center(frame_before, frame_after):
    """
    Extract the centre of the first detected person bounding box.
    We compare annotated frames — instead, detector.py is called separately,
    so we pass the raw detections through a lightweight re-use pattern.
    Returns (cx, cy) or None.
    """
    # detect_person() draws on the frame but doesn't return boxes.
    # For the wandering tracker we use a simple colour-independent approach:
    # re-run ultralytics on the frame to get boxes.
    return None  # placeholder — see _detect_and_get_center() below


def _detect_and_get_center(frame, yolo_model):
    """
    Run YOLO, draw boxes, and return the centre of the first person box.
    Returns (annotated_frame, (cx, cy) or None, boxes).
    """
    results = yolo_model(frame, classes=[0], verbose=False)
    annotated = results[0].plot()

    center = None
    boxes  = results[0].boxes
    if boxes is not None and len(boxes) > 0:
        # Take the highest-confidence person box
        best   = boxes[boxes.conf.argmax()]
        x1, y1, x2, y2 = best.xyxy[0].cpu().numpy()
        center = (int((x1 + x2) / 2), int((y1 + y2) / 2))

    return annotated, center, boxes


def initialize_camera():
    cap = cv2.VideoCapture(CAMERA_INDEX, cv2.CAP_DSHOW)
    if not cap.isOpened():
        raise Exception(" Error: Cannot open camera")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    return cap


def initialize_recorder():
    if not ENABLE_RECORDING:
        return None
    fourcc = cv2.VideoWriter_fourcc(*'XVID')
    return cv2.VideoWriter(OUTPUT_VIDEO_NAME, fourcc, TARGET_FPS, (FRAME_WIDTH, FRAME_HEIGHT))


# ---------------------------------------------------------------------------
# Main camera loop
# ---------------------------------------------------------------------------

def run_camera():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")

    # Load YOLO for person detection
    from ultralytics import YOLO
    yolo_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "yolov8n.pt")
    yolo = YOLO(yolo_path)

    model      = _load_model(device)
    pose_est   = PoseEstimator()
    wandering  = WanderingDetector()
    identifier = PatientIdentifier()

    cap      = initialize_camera()
    recorder = initialize_recorder()

    print(" Camera started successfully.")
    print(" Waiting for face recognition to identify patient...")
    print("Press 'q' to quit.")

    prev_time   = 0
    last_pred   = None
    last_conf   = 0.0
    # Temporal smoothing: average softmax probs over last 15 frames
    # to eliminate single-frame spikes (random FALL, etc.)
    SMOOTH_WINDOW     = 15
    CONFIDENCE_THRESH = 0.60   # below this → show "Uncertain"
    # FALL requires higher confidence — false alarms are worse than missed detections
    CLASS_THRESHOLDS  = {"FALL": 0.75, "CHEST_PAIN": 0.75}
    probs_buffer      = deque(maxlen=SMOOTH_WINDOW)

    while True:
        ret, frame = cap.read()
        if not ret:
            print(" Failed to grab frame.")
            break

        frame = cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT))
        raw_frame = frame.copy()  # Keep a clean copy for face recognition

        # 1️ Person Detection (YOLO) — get annotated frame + bbox centre + boxes
        frame, bbox_center, yolo_boxes = _detect_and_get_center(frame, yolo)

        # 2️ Face Recognition — identify patient from detected person
        patient_id = identifier.identify(raw_frame, yolo_boxes)

        # 3️ Pose Estimation (MediaPipe) — fills 64-frame sliding window
        frame, _ = pose_est.extract(frame, draw=True)

        # 4️ Activity Recognition (SkateFormer)
        if model is not None:
            sk_input = pose_est.get_skateformer_input()
            if sk_input is not None:
                probs = _predict(model, device, sk_input)
                probs_buffer.append(probs)
                # Average across recent frames to smooth out noise
                avg_probs = np.mean(probs_buffer, axis=0)
                best_id   = int(np.argmax(avg_probs))
                best_conf = float(avg_probs[best_id])
                pred_name = CLASS_NAMES[best_id]
                threshold = CLASS_THRESHOLDS.get(pred_name, CONFIDENCE_THRESH)
                if best_conf >= threshold:
                    last_pred = pred_name
                    last_conf = best_conf
                else:
                    last_pred = None   # show "Uncertain"
                    last_conf = best_conf

        # 5️ Wandering Detection (only meaningful when label is confident)
        wandering.update(last_pred or "", bbox_center)

        # 6️ Send events to Django API for alerting (only if patient identified)
        if last_pred == "FALL":
            _send_activity_event(patient_id, "FALL", last_conf)
        elif last_pred == "CHEST_PAIN":
            _send_activity_event(patient_id, "CHEST_PAIN", last_conf)
        if wandering.is_wandering:
            walk_secs = wandering._walk_frames / TARGET_FPS
            _send_activity_event(patient_id, "WALK", last_conf, is_wandering=True, walk_duration=walk_secs)

        # FPS control
        current_time = time.time()
        elapsed      = current_time - prev_time
        if elapsed < 1.0 / TARGET_FPS:
            continue
        fps       = 1.0 / elapsed if elapsed > 0 else 0
        prev_time = current_time

        # ----------------------------------------------------------------
        # Overlay rendering
        # ----------------------------------------------------------------

        # FPS
        cv2.putText(frame, f"FPS: {int(fps)}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

        # Patient identity
        if identifier.patient_name:
            id_text = f"Patient: {identifier.patient_name}"
            id_color = (0, 255, 0)
        else:
            id_text = "Patient: Identifying..."
            id_color = (0, 200, 255)
        cv2.putText(frame, id_text, (10, 65),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, id_color, 2)

        # Activity label
        if model is not None:
            if len(probs_buffer) < SMOOTH_WINDOW:
                act_text  = f"Collecting frames... ({len(probs_buffer)}/{SMOOTH_WINDOW})"
                act_color = (180, 180, 180)
            elif last_pred is not None:
                act_text  = f"{last_pred}  ({last_conf * 100:.1f}%)"
                act_color = LABEL_COLORS.get(last_pred, (0, 255, 0))
            else:
                act_text  = f"Uncertain  ({last_conf * 100:.1f}%)"
                act_color = (180, 180, 180)
            cv2.putText(frame, act_text, (10, 95),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.0, act_color, 2)

        # Wandering alert
        if wandering.is_wandering:
            cv2.putText(frame, " WANDERING DETECTED", (10, 135),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 2)

        # Fall alert (model-based, immediate)
        if last_pred == "FALL":
            cv2.putText(frame, " FALL DETECTED", (10, 175),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 0, 255), 3)

        cv2.imshow("SAVA - Alzheimer Monitoring", frame)

        if recorder:
            recorder.write(frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    pose_est.close()
    if recorder:
        recorder.release()
    cv2.destroyAllWindows()
    print(" Camera stopped cleanly.")
