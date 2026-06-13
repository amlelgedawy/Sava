import sys
import time
import threading
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    CAMERA_INDEX, FRAME_WIDTH, FRAME_HEIGHT,
    TARGET_FPS, ENABLE_RECORDING, OUTPUT_VIDEO_NAME,
    WANDERING_TORTUOSITY_THRESHOLD, WANDERING_BUFFER_FRAMES,
    WANDERING_MIN_WALK_SECONDS, PAIN_MODEL_PATH, PAIN_FRAME_INTERVAL, PAIN_BASELINE_FRAMES,
    PAIN_ALERT_THRESH, PAIN_ALERT_PERSIST,
    ACCEL_ENABLED, HEADLESS_MODE,
)
from detector import detect_person
from pose_estimator import PoseEstimator
from object_detector import DangerousObjectDetector
# Try to import PainClassifier (may fail in Docker due to relative imports)
try:
    from ..emotion_recognition.pain_classifier import PainClassifier
from ..emotion_recognition.pain_detector import PainDetector
except ImportError:
    try:
        from emotion_recognition.pain_classifier import PainClassifier
    except ImportError:
        PainClassifier = None

# ----------------------------
# SkateFormer paths & config
# ----------------------x------
import os
SKATEFORMER_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "SkateFormer")
CHECKPOINT      = Path(os.path.join(os.path.dirname(__file__), "work_dir", "sava_8class", "best_8class.pt"))
CLASS_NAMES     = ["EAT", "DRINK", "SLEEP", "FALL", "WALK", "SIT", "STAND", "USE_PHONE"]

# Overlay colours per label
LABEL_COLORS = {
    "EAT":       (0, 200, 255),  # yellow
    "DRINK":     (0, 200, 255),  # yellow
    "SLEEP":     (200, 200, 0),  # cyan
    "FALL":      (0, 0, 255),    # red — alert
    "WALK":      (0, 255, 0),    # green
    "SIT":       (255, 180, 0),  # orange
    "STAND":     (255, 255, 0),  # light blue
    "USE_PHONE": (180, 0, 255),  # purple
}


# ---------------------------------------------------------------------------
# Model loading & inference
# ---------------------------------------------------------------------------

def _load_model(device):
    """Load fine-tuned 8-class SkateFormer. Returns model or None if checkpoint missing."""
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
        num_classes=len(CLASS_NAMES),   # 8
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
    print(f" Loaded 8-class SkateFormer from {CHECKPOINT}")
    return model


@torch.no_grad()
def _predict(model, device, skateformer_input):
    """
    skateformer_input: ndarray (3, 64, 24, 2)
    Returns softmax probability vector (8,) as ndarray.
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
    "PAIN": 60,
    "WANDERING": 120,
    "DANGEROUS_OBJECT": 60,
}
_last_alert_time = {}

# Critical events that should be queued when patient_id is not yet available
_CRITICAL_ACTIVITIES = {"FALL", "PAIN"}
_pending_events = []          # list of dicts queued while patient_id is None
_PENDING_MAX = 20             # cap to avoid unbounded memory growth
_pending_lock = threading.Lock()


class PatientIdentifier:
    """
    Two-phase patient identification:
      Phase 1 (IDENTIFYING): Runs face recognition every FACE_RECOGNITION_INTERVAL
               seconds until a known patient is matched.
      Phase 2 (TRACKING):    Once identified, uses person tracking (embedding
               similarity) to maintain identity without re-running face
               recognition. Only falls back to Phase 1 if the tracked person
               is lost for TRACKING_LOST_THRESHOLD consecutive checks.

    All network I/O runs in a background thread so the camera loop never blocks.
    """

    # States
    STATE_IDENTIFYING = "IDENTIFYING"
    STATE_TRACKING = "TRACKING"

    # After this many consecutive tracking failures, fall back to face recognition
    TRACKING_LOST_THRESHOLD = 3
    # Embedding cosine-distance threshold — below this the person is "the same"
    EMBEDDING_SIMILARITY_THRESHOLD = 0.6

    def __init__(self):
        self.patient_id = None
        self.patient_name = None
        self.state = self.STATE_IDENTIFYING
        self._last_check = 0
        self._busy = False
        self._name_to_id_cache = {}
        # Tracking state
        self._known_embedding = None      # 128-d face embedding of identified patient
        self._tracking_lost_count = 0     # consecutive frames where tracking failed

    def identify(self, frame, yolo_boxes):
        """
        Non-blocking. Returns the cached patient_id immediately.
        Kicks off background work every FACE_RECOGNITION_INTERVAL seconds.
        """
        now = time.time()
        if self._busy or (now - self._last_check < FACE_RECOGNITION_INTERVAL):
            return self.patient_id
        self._last_check = now

        if yolo_boxes is None or len(yolo_boxes) == 0:
            # No person in frame
            if self.state == self.STATE_TRACKING:
                self._tracking_lost_count += 1
                if self._tracking_lost_count >= self.TRACKING_LOST_THRESHOLD:
                    self._transition_to_identifying("No person detected for multiple checks")
            return self.patient_id

        # Crop the best person detection
        best = yolo_boxes[yolo_boxes.conf.argmax()]
        x1, y1, x2, y2 = [int(v) for v in best.xyxy[0].cpu().numpy()]
        h, w = frame.shape[:2]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)
        person_crop = frame[y1:y2, x1:x2]

        if person_crop.size == 0:
            return self.patient_id

        _, buf = cv2.imencode(".jpg", person_crop)
        jpeg_bytes = buf.tobytes()

        self._busy = True
        if self.state == self.STATE_IDENTIFYING:
            threading.Thread(target=self._do_face_recognition, args=(jpeg_bytes,), daemon=True).start()
        else:
            threading.Thread(target=self._do_tracking, args=(jpeg_bytes,), daemon=True).start()

        return self.patient_id

    # ------------------------------------------------------------------
    # Phase 1: Face Recognition (runs until patient is identified)
    # ------------------------------------------------------------------
    def _do_face_recognition(self, jpeg_bytes):
        """Background thread: call /analyze-face to identify the patient."""
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
                return  # Keep trying next interval

            pid = self._resolve_patient_id(person_name)
            if pid:
                first_time = pid != self.patient_id
                self.patient_id = pid
                self.patient_name = person_name
                if first_time:
                    print(f" Patient identified: {person_name} (id={pid})")
                    _flush_pending_events(pid)

                # Get embedding for tracking via /track-person
                self._fetch_and_store_embedding(jpeg_bytes)

                # Transition to tracking phase
                self.state = self.STATE_TRACKING
                self._tracking_lost_count = 0
                print(f" Switching to person tracking mode")

        except Exception:
            pass
        finally:
            self._busy = False

    def _fetch_and_store_embedding(self, jpeg_bytes):
        """Call /track-person to get and store the face embedding."""
        try:
            resp = requests.post(
                f"{AI_FACE_SERVER_URL}/track-person",
                files={"frame": ("face.jpg", jpeg_bytes, "image/jpeg")},
                data={"patient_id": self.patient_id or "camera_auto"},
                timeout=5,
            )
            if resp.status_code == 200:
                data = resp.json()
                if data.get("face_detected") and data.get("embedding"):
                    self._known_embedding = data["embedding"]
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Phase 2: Person Tracking (maintains identity via embedding similarity)
    # ------------------------------------------------------------------
    def _do_tracking(self, jpeg_bytes):
        """Background thread: call /track-person and compare embeddings."""
        try:
            resp = requests.post(
                f"{AI_FACE_SERVER_URL}/track-person",
                files={"frame": ("face.jpg", jpeg_bytes, "image/jpeg")},
                data={"patient_id": self.patient_id or "camera_auto"},
                timeout=5,
            )
            if resp.status_code != 200:
                self._tracking_lost_count += 1
                self._check_lost()
                return

            data = resp.json()

            if not data.get("face_detected") or not data.get("embedding"):
                # Face not visible — tolerate a few misses before resetting
                self._tracking_lost_count += 1
                self._check_lost()
                return

            current_embedding = data["embedding"]

            if self._known_embedding is not None:
                dist = self._cosine_distance(self._known_embedding, current_embedding)
                if dist <= self.EMBEDDING_SIMILARITY_THRESHOLD:
                    # Same person — reset lost counter, update embedding
                    self._tracking_lost_count = 0
                    self._known_embedding = current_embedding
                else:
                    # Different person detected
                    self._tracking_lost_count += 1
                    print(f" Tracking: different person detected (distance={dist:.2f})")
                    self._check_lost()
            else:
                # No stored embedding — store this one
                self._known_embedding = current_embedding
                self._tracking_lost_count = 0

        except Exception:
            self._tracking_lost_count += 1
            self._check_lost()
        finally:
            self._busy = False

    @staticmethod
    def _cosine_distance(emb_a, emb_b):
        """Compute cosine distance between two embedding vectors."""
        import numpy as _np
        a = _np.array(emb_a)
        b = _np.array(emb_b)
        dot = _np.dot(a, b)
        norm = (_np.linalg.norm(a) * _np.linalg.norm(b))
        if norm == 0:
            return 1.0
        return 1.0 - (dot / norm)

    def _check_lost(self):
        """If lost count exceeds threshold, transition back to face recognition."""
        if self._tracking_lost_count >= self.TRACKING_LOST_THRESHOLD:
            self._transition_to_identifying("Person lost during tracking")

    def _transition_to_identifying(self, reason):
        """Clear identity and switch back to face recognition phase."""
        if self.patient_id is not None:
            print(f" {reason} -- switching to face recognition mode")
        self.patient_id = None
        self.patient_name = None
        self._known_embedding = None
        self._tracking_lost_count = 0
        self.state = self.STATE_IDENTIFYING

    # ------------------------------------------------------------------
    # Shared helper
    # ------------------------------------------------------------------
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
    Critical events (FALL, CHEST_PAIN) are queued if patient_id is unavailable
    and automatically flushed once the patient is identified.
    """
    if not patient_id:
        if activity in _CRITICAL_ACTIVITIES:
            with _pending_lock:
                if len(_pending_events) < _PENDING_MAX:
                    _pending_events.append({
                        "activity": activity,
                        "confidence": float(confidence),
                        "is_wandering": is_wandering,
                        "walk_duration": float(walk_duration),
                        "queued_at": time.time(),
                    })
                    print(f"\u26a0\ufe0f  {activity} queued — waiting for patient identification ({len(_pending_events)} pending)")
        return

    # Flush any events that were queued before patient_id was available
    _flush_pending_events(patient_id)

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
                timeout=15,  # Increased API timeout from 5s to 15s
            )
            if resp.status_code == 201:
                data = resp.json()
                alerts = data.get("alerts_created", 0)
                if alerts > 0:
                    print(f"\U0001f6a8 Alert sent: {activity} -> {alerts} caregiver(s) notified")
                else:
                    print(f"    Event sent: {activity} (no new alert — cooldown or known person)")
            else:
                print(f"Django API error: {resp.status_code} — {resp.text[:200]}")
        except Exception as e:
            print(f" Could not reach Django API: {e}")

    threading.Thread(target=_post, daemon=True).start()


def _flush_pending_events(patient_id):
    """
    Send all queued critical events now that patient_id is available.
    Called automatically when face recognition resolves the patient.
    """
    with _pending_lock:
        events = list(_pending_events)
        _pending_events.clear()

    if not events:
        return

    print(f"\U0001f4e4 Flushing {len(events)} queued event(s) for patient {patient_id}")
    for evt in events:
        _send_activity_event(
            patient_id,
            evt["activity"],
            evt["confidence"],
            is_wandering=evt["is_wandering"],
            walk_duration=evt["walk_duration"],
        )


def _send_object_detection_event(patient_id, detections):
    """
    POST dangerous object detection events to Django API in a background thread.
    Each detection becomes a separate event. Respects cooldown per object class.
    """
    if not patient_id or not detections:
        return

    now = time.time()
    events_to_send = []
    for det in detections:
        key = f"DANGEROUS_OBJECT_{det['label']}"
        cooldown = _ALERT_COOLDOWNS.get("DANGEROUS_OBJECT", 60)
        if now - _last_alert_time.get(key, 0) < cooldown:
            continue
        _last_alert_time[key] = now
        events_to_send.append(det)

    if not events_to_send:
        return

    def _post():
        for det in events_to_send:
            try:
                resp = requests.post(
                    f"{DJANGO_API_URL}/object-detection/event",
                    json={
                        "patient_id": patient_id,
                        "label": det["label"],
                        "confidence": det["confidence"],
                        "danger_level": det["danger_level"],
                        "box": det.get("box_norm", {}),
                    },
                    timeout=15,
                )
                if resp.status_code == 201:
                    data = resp.json()
                    alerts = data.get("alerts_created", 0)
                    level = det["danger_level"]
                    if alerts > 0:
                        print(f"\U0001f6a8 DANGEROUS OBJECT [{level}]: {det['label']} ({det['confidence']:.0%}) -> {alerts} alert(s) sent")
                    else:
                        print(f"    Object event: {det['label']} [{level}] (no new alert — cooldown)")
                else:
                    print(f"Django API error (object detection): {resp.status_code} — {resp.text[:200]}")
            except Exception as e:
                print(f" Could not send object event: {e}")

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
    Run YOLO, draw boxes, and return centre + all boxes + best person bbox.
    Returns (annotated_frame, (cx, cy) or None, boxes, (x1,y1,x2,y2) or None).
    boxes       — all YOLO person boxes (needed by PatientIdentifier)
    person_bbox — single best-confidence bbox tuple (needed for pain crop)
    """
    results   = yolo_model(frame, classes=[0], verbose=False, device='cpu')
    annotated = results[0].plot()

    center = None
    bbox   = None
    boxes  = results[0].boxes
    if boxes is not None and len(boxes) > 0:
        best            = boxes[boxes.conf.argmax()]
        x1, y1, x2, y2 = best.xyxy[0].cpu().numpy()
        center          = (int((x1 + x2) / 2), int((y1 + y2) / 2))
        bbox            = (int(x1), int(y1), int(x2), int(y2))

    return annotated, center, boxes, bbox


def _face_crop_from_bbox(frame, bbox):
    """
    Crop the upper 30% of a YOLO person bounding box as a face region.
    Returns the face crop, or None if bbox is invalid.
    """
    if bbox is None:
        return None
    x1, y1, x2, y2 = bbox
    h, w            = frame.shape[:2]
    face_y2         = int(y1 + (y2 - y1) * 0.30)
    x1c             = max(0, x1)
    y1c             = max(0, y1)
    x2c             = min(w, x2)
    y2c             = min(h, face_y2)
    if x2c <= x1c or y2c <= y1c:
        return None
    return frame[y1c:y2c, x1c:x2c]


def initialize_camera():
    cap = cv2.VideoCapture(CAMERA_INDEX)
    if not cap.isOpened():
        raise Exception("❌ Error: Cannot open camera")
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

    obj_detector = DangerousObjectDetector()
    obj_loaded = obj_detector.load()
    if not obj_loaded:
        print("⚠️  Object detection disabled — model not found.")

    # Accelerometer — graceful fallback if hardware not connected or smbus2 not installed
    accel = None
    if ACCEL_ENABLED:
        try:
            from .accelerometer import AccelerometerReader
            accel = AccelerometerReader()
            accel.start()
            print("✅ Accelerometer (MPU-6050) connected.")
        except Exception as e:
            print(f"⚠️  Accelerometer not available ({e}). Using camera-only fall detection.")
    # emotion_det = EmotionDetector(device)   # dropped — lowest priority
    pain_det = PainDetector(PAIN_BASELINE_FRAMES)
    pain_clf = None
    if PainClassifier is not None:
        try:
            pain_clf = PainClassifier(PAIN_MODEL_PATH, device)
            print(" Pain classifier loaded.")
        except Exception as e:
            print(f" Pain classifier not available: {e}")

    cap      = initialize_camera()
    recorder = initialize_recorder()

    print(" Camera started successfully.")
    print(" Waiting for face recognition to identify patient...")
    print("Press 'q' to quit.")

    prev_time      = 0
    last_pred      = None
    last_conf      = 0.0
    fall_consec    = 0
    drink_consec   = 0
    last_pain_prob = None   # float 0-100 or None when model not trained
    pain_consec    = 0
    frame_count    = 0
    SMOOTH_WINDOW      = 15
    CONFIDENCE_THRESH  = 0.75   # raised from 0.60 to cut wrong guesses
    CLASS_THRESHOLDS   = {"FALL": 0.75}
    FALL_PERSIST_FRAMES  = 10
    DRINK_PERSIST_FRAMES = 8     # DRINK must hold N frames before showing
    DRINK_EAT_MARGIN     = 0.15  # if DRINK barely beats EAT, prefer EAT
    probs_buffer         = deque(maxlen=SMOOTH_WINDOW)

    while True:
        ret, frame = cap.read()
        if not ret:
            print(" Failed to grab frame.")
            break

        frame = cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT))
        raw_frame = frame.copy()  # Keep a clean copy for face recognition

        # 1️⃣ Person Detection (YOLO) — boxes for face recognition, bbox for pain crop
        frame, bbox_center, yolo_boxes, person_bbox = _detect_and_get_center(frame, yolo)

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

                # Margin check: if DRINK barely beats EAT, prefer EAT
                if last_pred == "DRINK":
                    drink_prob = float(avg_probs[CLASS_NAMES.index("DRINK")])
                    eat_prob   = float(avg_probs[CLASS_NAMES.index("EAT")])
                    if drink_prob - eat_prob < DRINK_EAT_MARGIN:
                        last_pred = "EAT"
                        last_conf = eat_prob

        # DRINK persistence gate: suppress until sustained for N frames
        if last_pred == "DRINK":
            drink_consec += 1
            if drink_consec < DRINK_PERSIST_FRAMES:
                last_pred = None
        else:
            drink_consec = 0

        # FALL persistence counter
        if last_pred == "FALL":
            fall_consec += 1
        else:
            fall_consec = 0

        # 5️ Dangerous Object Detection (runs every OBJECT_DETECTION_INTERVAL seconds)
        obj_detections = obj_detector.detect(raw_frame)

        # 6️ Wandering Detection (only meaningful when label is confident)
        wandering.update(last_pred or "", bbox_center)

        # 7️ Send events to Django API for alerting (only if patient identified)
        #    Read identifier.patient_id directly — the local variable may be stale
        #    if the background face-recognition thread updated it mid-frame.
        current_pid = identifier.patient_id
        if last_pred == "FALL":
            _send_activity_event(current_pid, "FALL", last_conf)

        # Pain alert persistence counter (same pattern as fall detection)
        if last_pain_prob is not None and last_pain_prob >= PAIN_ALERT_THRESH:
            pain_consec += 1
        else:
            pain_consec = 0
        if pain_consec >= PAIN_ALERT_PERSIST:
            _send_activity_event(current_pid, "PAIN", last_pain_prob / 100.0)

        if wandering.is_wandering:
            walk_secs = wandering._walk_frames / TARGET_FPS
            _send_activity_event(current_pid, "WALK", last_conf, is_wandering=True, walk_duration=walk_secs)
        if obj_detections:
            _send_object_detection_event(current_pid, obj_detections)

        # FPS control
        current_time = time.time()
        elapsed      = current_time - prev_time
        if elapsed < 1.0 / TARGET_FPS:
            continue
        fps       = 1.0 / elapsed if elapsed > 0 else 0
        prev_time = current_time

        # 5️⃣ Pain Detection — py-feat AU detector on full frame (finds face itself)
        #    Falls back to EfficientNet-B0 when pain_efficientnet_b0.pt is available.
        frame_count += 1
        if frame_count % PAIN_FRAME_INTERVAL == 0:
            if pain_clf._model is not None:
                face_crop = _face_crop_from_bbox(frame, person_bbox)
                if face_crop is not None:
                    last_pain_prob = pain_clf.predict(face_crop)
            else:
                last_pain_prob = pain_det.predict(frame)

        # ----------------------------------------------------------------
        # Overlay rendering
        # ----------------------------------------------------------------

        # FPS
        cv2.putText(frame, f"FPS: {int(fps)}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

        # Patient identity
        if identifier.patient_name and identifier.state == identifier.STATE_TRACKING:
            id_text = f"Patient: {identifier.patient_name} [Tracking]"
            id_color = (0, 255, 0)
        elif identifier.patient_name:
            id_text = f"Patient: {identifier.patient_name}"
            id_color = (0, 255, 0)
        elif identifier.state == identifier.STATE_IDENTIFYING and identifier._last_check > 0:
            id_text = "Patient: Identifying..."
            id_color = (0, 200, 255)
        else:
            id_text = "Patient: Waiting..."
            id_color = (180, 180, 180)
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

        # Pain overlay
        if pain_det.calibrating:
            pain_text  = f"Pain: calibrating... ({pain_det.calibration_count}/{PAIN_BASELINE_FRAMES})"
            pain_color = (100, 100, 100)
        elif last_pain_prob is not None:
            pain_text  = f"Pain: {last_pain_prob:.0f}%"
            pain_color = (200, 200, 200)
        else:
            pain_text  = "Pain: --"
            pain_color = (100, 100, 100)
        cv2.putText(frame, pain_text, (10, 130),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.75, pain_color, 2)

        # Wandering alert
        if wandering.is_wandering:
            cv2.putText(frame, "⚠ WANDERING DETECTED", (10, 165),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 2)

        # Fall alert — camera + accelerometer fusion
        camera_fall  = fall_consec >= FALL_PERSIST_FRAMES
        accel_impact = accel.recent_impact   if accel else False
        accel_alone  = accel.standalone_fall if accel else False
        # Primary:     camera sees FALL for N frames AND accelerometer confirms impact
        # Safety net:  accelerometer alone detects very hard impact (covers out-of-view falls)
        if (camera_fall and accel_impact) or accel_alone:
            cv2.putText(frame, "FALL DETECTED", (10, 200),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 0, 255), 3)

        # Pain alert
        if pain_consec >= PAIN_ALERT_PERSIST:
            cv2.putText(frame, "PAIN DETECTED", (10, 235),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 100, 255), 3)

        # Dangerous object overlays (bounding boxes + labels on frame)
        if obj_detector.is_loaded and obj_detector.last_detections:
            frame = obj_detector.draw_detections(frame)
            y_off = 215
            for det in obj_detector.last_detections:
                obj_text = f"DANGER: {det['label'].upper()} [{det['danger_level']}]"
                cv2.putText(frame, obj_text, (10, y_off),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
                y_off += 30

        if not HEADLESS_MODE:
            cv2.imshow("SAVA - Alzheimer Monitoring", frame)

        if recorder:
            recorder.write(frame)

        if not HEADLESS_MODE and cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    pose_est.close()
    if accel:
        accel.stop()
    pain_det.close()
    if recorder:
        recorder.release()
    if not HEADLESS_MODE:
        cv2.destroyAllWindows()
    print(" Camera stopped cleanly.")
