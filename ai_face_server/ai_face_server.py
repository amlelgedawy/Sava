import os
import json
import time
import tempfile
import threading
from datetime import datetime
from typing import Tuple, List, Dict

import cv2
import numpy as np
import joblib
from sklearn.svm import SVC
from sklearn.preprocessing import LabelEncoder

from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks
from fastapi.responses import JSONResponse

import face_recognition

app = FastAPI(title="SAVA Face AI Server", version="2.2")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

RELATIVES_DIR = os.path.join(BASE_DIR, "uploads", "relatives")
MODELS_DIR = os.path.join(BASE_DIR, "models")
os.makedirs(RELATIVES_DIR, exist_ok=True)
os.makedirs(MODELS_DIR, exist_ok=True)

# Fallback matching tolerance (only used if model not trained yet)
TOLERANCE = float(os.getenv("FACE_TOLERANCE", "0.5"))

# Enrollment settings (tuned to be less strict by default)
ENROLL_SAMPLE_EVERY_N_FRAMES = int(os.getenv("ENROLL_SAMPLE_EVERY_N_FRAMES", "2"))
MIN_FACE_SIZE_PX = int(os.getenv("MIN_FACE_SIZE_PX", "80"))
BLUR_THRESHOLD = float(os.getenv("BLUR_THRESHOLD", "30"))
MIN_EMB_SEPARATION = float(os.getenv("MIN_EMB_SEPARATION", "0.05"))
ENROLL_MAX_FACES = int(os.getenv("ENROLL_MAX_FACES", "80"))

# Unknown decision thresholds (can tune later)
UNKNOWN_PROB_THRESHOLD = float(os.getenv("UNKNOWN_PROB_THRESHOLD", "0.60"))
UNKNOWN_DIST_THRESHOLD = float(os.getenv("UNKNOWN_DIST_THRESHOLD", "0.65"))

TRAIN_LOCK = threading.Lock()
TRAINING_STATE = {
    "is_training": False,
    "last_trained_at": None,
    "last_train_status": None,
    "last_train_error": None,
}


# ---------------------------
# Utilities
# ---------------------------

def _save_json(path: str, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _load_json(path: str, default):
    if not os.path.exists(path):
        return default
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _variance_of_laplacian(gray: np.ndarray) -> float:
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def _embedding_distance(a, b) -> float:
    a = np.array(a, dtype=np.float32)
    b = np.array(b, dtype=np.float32)
    return float(np.linalg.norm(a - b))


def _ensure_person_dirs(person_name: str) -> Tuple[str, str, str]:
    """Returns (person_dir, faces_dir, embeddings_path)."""
    person_dir = os.path.join(RELATIVES_DIR, person_name)
    faces_dir = os.path.join(person_dir, "faces")
    os.makedirs(faces_dir, exist_ok=True)
    emb_path = os.path.join(person_dir, "embeddings.json")
    return person_dir, faces_dir, emb_path


def _iter_people_embeddings():
    """Return list of (person_name, embeddings_list)."""
    if not os.path.isdir(RELATIVES_DIR):
        return []

    people = []
    for person_name in os.listdir(RELATIVES_DIR):
        person_dir = os.path.join(RELATIVES_DIR, person_name)
        emb_path = os.path.join(person_dir, "embeddings.json")
        if os.path.isdir(person_dir) and os.path.exists(emb_path):
            embs = _load_json(emb_path, default=[])
            if len(embs) >= 5:
                people.append((person_name, embs))
    return people


def _artifacts_exist() -> bool:
    return all([
        os.path.exists(os.path.join(MODELS_DIR, "face_svm.joblib")),
        os.path.exists(os.path.join(MODELS_DIR, "label_encoder.joblib")),
        os.path.exists(os.path.join(MODELS_DIR, "centroids.joblib")),
    ])


def _load_artifacts():
    svm_path = os.path.join(MODELS_DIR, "face_svm.joblib")
    le_path = os.path.join(MODELS_DIR, "label_encoder.joblib")
    cen_path = os.path.join(MODELS_DIR, "centroids.joblib")
    if not (os.path.exists(svm_path) and os.path.exists(le_path) and os.path.exists(cen_path)):
        return None, None, None
    clf = joblib.load(svm_path)
    le = joblib.load(le_path)
    centroids = joblib.load(cen_path)
    return clf, le, centroids


def _dist_to_centroid(emb: np.ndarray, centroid: List[float]) -> float:
    return float(np.linalg.norm(emb.astype(np.float32) - np.array(centroid, dtype=np.float32)))


def _read_image_bgr(path: str) -> np.ndarray:
    img = cv2.imread(path)
    if img is None:
        raise ValueError("Failed to read image using OpenCV.")
    return img


def _rotate_bgr(img_bgr: np.ndarray, k: int) -> np.ndarray:
    """Rotate image by 90*k degrees clockwise. k in {0,1,2,3}."""
    if k == 0:
        return img_bgr
    if k == 1:
        return cv2.rotate(img_bgr, cv2.ROTATE_90_CLOCKWISE)
    if k == 2:
        return cv2.rotate(img_bgr, cv2.ROTATE_180)
    return cv2.rotate(img_bgr, cv2.ROTATE_90_COUNTERCLOCKWISE)


def _find_single_face_with_rotation(frame_bgr: np.ndarray):
    """
    Try rotations 0/90/180/270 to find exactly 1 face.
    Returns:
      (upright_bgr, rgb, locations, rotation_k)
    or (None, None, None, None)
    """
    for k in (0, 1, 2, 3):
        rot_bgr = _rotate_bgr(frame_bgr, k)
        rgb = cv2.cvtColor(rot_bgr, cv2.COLOR_BGR2RGB)
        locations = face_recognition.face_locations(rgb)
        if len(locations) == 1:
            return rot_bgr, rgb, locations, k
    return None, None, None, None


# ---------------------------
# Training
# ---------------------------

def train_face_svm_internal():
    """Train SVM from saved embeddings. Called automatically after enrollment."""
    global TRAINING_STATE

    if not TRAIN_LOCK.acquire(blocking=False):
        return  # training already running

    try:
        TRAINING_STATE["is_training"] = True
        TRAINING_STATE["last_train_status"] = "running"
        TRAINING_STATE["last_train_error"] = None

        people = _iter_people_embeddings()
        if len(people) < 2:
            TRAINING_STATE["last_train_status"] = "skipped"
            TRAINING_STATE["last_train_error"] = "Need >=2 people with >=5 embeddings each."
            return

        X, y = [], []
        centroids: Dict[str, List[float]] = {}

        for person_name, embs in people:
            arr = np.array(embs, dtype=np.float32)
            for e in arr:
                X.append(e)
                y.append(person_name)
            centroids[person_name] = arr.mean(axis=0).tolist()

        X = np.array(X, dtype=np.float32)
        y = np.array(y)

        le = LabelEncoder()
        y_enc = le.fit_transform(y)

        clf = SVC(kernel="rbf", probability=True, class_weight="balanced")
        clf.fit(X, y_enc)

        joblib.dump(clf, os.path.join(MODELS_DIR, "face_svm.joblib"))
        joblib.dump(le, os.path.join(MODELS_DIR, "label_encoder.joblib"))
        joblib.dump(centroids, os.path.join(MODELS_DIR, "centroids.joblib"))

        TRAINING_STATE["last_trained_at"] = datetime.utcnow().isoformat()
        TRAINING_STATE["last_train_status"] = "ok"
        TRAINING_STATE["last_train_error"] = None

    except Exception as e:
        TRAINING_STATE["last_train_status"] = "error"
        TRAINING_STATE["last_train_error"] = str(e)

    finally:
        TRAINING_STATE["is_training"] = False
        TRAIN_LOCK.release()


# ---------------------------
# Fallback flat encodings (optional)
# ---------------------------

def load_known_encodings_flat() -> Tuple[List, List[str]]:
    """
    Fallback: load encodings from uploads/relatives/*.jpg|png (old behavior).
    Note: this only works if you keep single images directly inside RELATIVES_DIR.
    """
    if not os.path.isdir(RELATIVES_DIR):
        return [], []

    files = [
        f for f in os.listdir(RELATIVES_DIR)
        if f.lower().endswith((".jpg", ".jpeg", ".png"))
    ]
    if not files:
        return [], []

    known_encodings = []
    known_keys = []

    for filename in files:
        path = os.path.join(RELATIVES_DIR, filename)
        name_key = os.path.splitext(filename)[0]

        try:
            img = face_recognition.load_image_file(path)
            encs = face_recognition.face_encodings(img)
            if not encs:
                continue
            known_encodings.append(encs[0])
            known_keys.append(name_key)
        except Exception:
            continue

    return known_encodings, known_keys


# ---------------------------
# Routes
# ---------------------------

@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/training-status")
def training_status():
    return {"status": "ok", **TRAINING_STATE, "artifacts_exist": _artifacts_exist()}


@app.post("/enroll-relative")
async def enroll_relative(
    background_tasks: BackgroundTasks,
    person_name: str = Form(...),
    video: UploadFile = File(...),
):
    """
    Enrollment:
      - Upload video
      - Extract good face crops + embeddings
      - Auto-train SVM in background
    Includes debug counters in response.
    Handles rotated videos by trying 0/90/180/270 rotations.
    """
    person_name = (person_name or "").strip().lower()
    if not person_name:
        return JSONResponse(status_code=400, content={"status": "error", "message": "person_name is required"})

    person_dir, faces_dir, emb_path = _ensure_person_dirs(person_name)
    embeddings = _load_json(emb_path, default=[])

    tmp_video_path = os.path.join(person_dir, f"_tmp_{int(time.time())}_{video.filename or 'video.mp4'}")

    saved = 0
    frame_idx = 0
    last_kept_emb = None

    debug = {
        "frames_read": 0,
        "sampled": 0,
        "blur_reject": 0,
        "no_single_face": 0,
        "small_face": 0,
        "no_encoding": 0,
        "duplicate": 0,
        "saved": 0,
        "rotation_counts": {"0": 0, "1": 0, "2": 0, "3": 0},
        "last_blur": None,
        "last_face_box": None,
    }

    try:
        with open(tmp_video_path, "wb") as f:
            f.write(await video.read())

        cap = cv2.VideoCapture(tmp_video_path)
        if not cap.isOpened():
            return JSONResponse(status_code=400, content={"status": "error", "message": "Failed to open video"})

        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break

            debug["frames_read"] += 1
            frame_idx += 1

            if frame_idx % ENROLL_SAMPLE_EVERY_N_FRAMES != 0:
                continue
            debug["sampled"] += 1

            gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
            blur = _variance_of_laplacian(gray)
            debug["last_blur"] = blur
            if blur < BLUR_THRESHOLD:
                debug["blur_reject"] += 1
                continue

            upright_bgr, rgb, locations, k = _find_single_face_with_rotation(frame_bgr)
            if upright_bgr is None:
                debug["no_single_face"] += 1
                continue

            debug["rotation_counts"][str(k)] += 1

            top, right, bottom, left = locations[0]
            w = right - left
            h = bottom - top
            debug["last_face_box"] = {"w": int(w), "h": int(h)}

            if w < MIN_FACE_SIZE_PX or h < MIN_FACE_SIZE_PX:
                debug["small_face"] += 1
                continue

            encs = face_recognition.face_encodings(rgb, known_face_locations=locations)
            if not encs:
                debug["no_encoding"] += 1
                continue

            emb = encs[0].tolist()

            if last_kept_emb is not None:
                if _embedding_distance(last_kept_emb, emb) < MIN_EMB_SEPARATION:
                    debug["duplicate"] += 1
                    continue

            crop = upright_bgr[top:bottom, left:right]
            ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")
            out_path = os.path.join(faces_dir, f"{person_name}_{ts}.jpg")
            cv2.imwrite(out_path, crop)

            embeddings.append(emb)
            last_kept_emb = emb
            saved += 1
            debug["saved"] += 1

            if saved >= ENROLL_MAX_FACES:
                break

        cap.release()

        if len(embeddings) > 400:
            embeddings = embeddings[-400:]

        _save_json(emb_path, embeddings)

        background_tasks.add_task(train_face_svm_internal)

        return {
            "status": "ok",
            "person_name": person_name,
            "faces_saved_now": saved,
            "total_embeddings": len(embeddings),
            "auto_train": "scheduled",
            "debug": debug,
            "config": {
                "ENROLL_SAMPLE_EVERY_N_FRAMES": ENROLL_SAMPLE_EVERY_N_FRAMES,
                "MIN_FACE_SIZE_PX": MIN_FACE_SIZE_PX,
                "BLUR_THRESHOLD": BLUR_THRESHOLD,
                "MIN_EMB_SEPARATION": MIN_EMB_SEPARATION,
            }
        }

    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

    finally:
        try:
            if os.path.exists(tmp_video_path):
                os.remove(tmp_video_path)
        except Exception:
            pass


@app.post("/analyze-face")
async def analyze_face(
    patient_id: str = Form(...),
    frame: UploadFile = File(...),
):
    """
    Returns standardized JSON for Django.
    Handles rotated images by trying 0/90/180/270 rotations.
    """
    tmp_path = None
    try:
        suffix = os.path.splitext(frame.filename or "")[1] or ".jpg"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp_path = tmp.name
            tmp.write(await frame.read())

        try:
            frame_bgr = _read_image_bgr(tmp_path)
        except Exception as e:
            return JSONResponse(status_code=400, content={"status": "error", "message": f"Failed to read image: {str(e)}"})

        upright_bgr, rgb, locations, rot_k = _find_single_face_with_rotation(frame_bgr)
        if upright_bgr is None:
            return {
                "event_type": "FACE",
                "confidence": 0.0,
                "payload": {"known": True, "person_name": None, "status": "no_face"},
                "raw": {"status": "no_face"},
            }

        unknown_encodings = face_recognition.face_encodings(rgb, known_face_locations=locations)
        if not unknown_encodings:
            return {
                "event_type": "FACE",
                "confidence": 0.0,
                "payload": {"known": True, "person_name": None, "status": "no_face"},
                "raw": {"status": "no_face"},
            }

        emb = unknown_encodings[0]

        clf, le, centroids = _load_artifacts()
        if clf is not None:
            probs = clf.predict_proba([emb])[0]
            best_idx = int(np.argmax(probs))
            best_prob = float(probs[best_idx])
            pred_name = le.inverse_transform([best_idx])[0]

            centroid = centroids.get(pred_name)
            dist = _dist_to_centroid(emb, centroid) if centroid is not None else 999.0

            is_unknown = (best_prob < UNKNOWN_PROB_THRESHOLD) or (dist > UNKNOWN_DIST_THRESHOLD)

            if is_unknown:
                return {
                    "event_type": "FACE",
                    "confidence": best_prob,
                    "payload": {"known": False, "person_name": None, "status": "unknown"},
                    "raw": {"predicted": pred_name, "prob": best_prob, "dist": dist, "rotation_k": rot_k},
                }

            return {
                "event_type": "FACE",
                "confidence": best_prob,
                "payload": {"known": True, "person_name": pred_name, "status": "match"},
                "raw": {"predicted": pred_name, "prob": best_prob, "dist": dist, "rotation_k": rot_k},
            }

        known_encodings, known_keys = load_known_encodings_flat()
        if not known_encodings:
            return {
                "event_type": "FACE",
                "confidence": 1.0,
                "payload": {"known": False, "person_name": None, "status": "no_known_faces"},
                "raw": {"status": "no_known_faces", "rotation_k": rot_k},
            }

        matches = face_recognition.compare_faces(known_encodings, emb, tolerance=TOLERANCE)
        if True in matches:
            idx = matches.index(True)
            return {
                "event_type": "FACE",
                "confidence": 1.0,
                "payload": {"known": True, "person_name": known_keys[idx], "status": "match"},
                "raw": {"status": "match", "name_key": known_keys[idx], "confidence": 1.0, "rotation_k": rot_k},
            }

        return {
            "event_type": "FACE",
            "confidence": 1.0,
            "payload": {"known": False, "person_name": None, "status": "no_match"},
            "raw": {"status": "no_match", "confidence": 1.0, "rotation_k": rot_k},
        }

    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

    finally:
        try:
            if tmp_path and os.path.exists(tmp_path):
                os.remove(tmp_path)
        except Exception:
            pass
