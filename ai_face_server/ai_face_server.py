import os
import tempfile
from typing import Tuple, List

from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse

import face_recognition

app = FastAPI(title="SAVA Face AI Server", version="1.0")

# Store known faces here (self-contained for the AI server)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RELATIVES_DIR = os.path.join(BASE_DIR, "uploads", "relatives")

# Matching tolerance (lower = stricter)
TOLERANCE = float(os.getenv("FACE_TOLERANCE", "0.5"))


def load_known_encodings() -> Tuple[List, List[str]]:
    """Loads encodings from uploads/relatives/*.jpg|png and returns (encodings, keys)."""
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


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/analyze-face")
async def analyze_face(
    patient_id: str = Form(...),
    frame: UploadFile = File(...)
):
    """
    Input:
      multipart/form-data:
        - patient_id: string
        - frame: image file

    Output (standardized for backend):
      {
        "event_type": "FACE",
        "confidence": 0.0..1.0,
        "payload": {"known": bool, "person_name": str|null, "status": str},
        "raw": {...}
      }
    """
    tmp_path = None
    try:
        # Save upload to temp file
        suffix = os.path.splitext(frame.filename or "")[1] or ".jpg"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp_path = tmp.name
            tmp.write(await frame.read())

        # Encode unknown face
        try:
            unknown_image = face_recognition.load_image_file(tmp_path)
        except Exception as e:
            return JSONResponse(
                status_code=400,
                content={"status": "error", "message": f"Failed to load image: {str(e)}"},
            )

        unknown_encodings = face_recognition.face_encodings(unknown_image)
        if not unknown_encodings:
            # No face found => not a risky event
            return {
                "event_type": "FACE",
                "confidence": 0.0,
                "payload": {"known": True, "person_name": None, "status": "no_face"},
                "raw": {"status": "no_face"},
            }

        unknown_encoding = unknown_encodings[0]

        # Load known faces
        known_encodings, known_keys = load_known_encodings()
        if not known_encodings:
            # No registered relatives => treat any detected face as unknown
            return {
                "event_type": "FACE",
                "confidence": 1.0,
                "payload": {"known": False, "person_name": None, "status": "no_known_faces"},
                "raw": {"status": "no_known_faces"},
            }

        # Compare
        matches = face_recognition.compare_faces(known_encodings, unknown_encoding, tolerance=TOLERANCE)

        if True in matches:
            idx = matches.index(True)
            return {
                "event_type": "FACE",
                "confidence": 1.0,
                "payload": {"known": True, "person_name": known_keys[idx], "status": "match"},
                "raw": {"status": "match", "name_key": known_keys[idx], "confidence": 1.0},
            }

        return {
            "event_type": "FACE",
            "confidence": 1.0,
            "payload": {"known": False, "person_name": None, "status": "no_match"},
            "raw": {"status": "no_match", "confidence": 1.0},
        }

    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

    finally:
        try:
            if tmp_path and os.path.exists(tmp_path):
                os.remove(tmp_path)
        except Exception:
            pass
