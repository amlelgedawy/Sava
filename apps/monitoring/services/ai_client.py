import requests
from django.conf import settings

class AIClientError(Exception):
    pass


def detect_objects(image_file) -> dict:
    """
    Sends multipart image to the Object Detection server and returns JSON result.
    Expected JSON shape:
      {
        "detections": [
          {
            "label": "knife",
            "confidence": 0.87,
            "danger_level": "HIGH",
            "is_dangerous": true,
            "box": {"x1": 0.1, "y1": 0.2, "x2": 0.4, "y2": 0.6}
          }
        ]
      }
    """
    url = settings.OBJECT_DETECTION_SERVER_URL.rstrip("/") + "/detect"

    files = {
        "frame": (getattr(image_file, "name", "frame.jpg"), image_file, getattr(image_file, "content_type", "image/jpeg"))
    }

    try:
        resp = requests.post(url, files=files, timeout=10)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        raise AIClientError(f"Object detection server request failed: {str(e)}")

def analyze_face(image_file, patient_id: str) -> dict:
    """
    Sends multipart image to AI server and returns JSON result.
    Expected JSON shape example:
      {
        "event_type": "FACE",
        "confidence": 0.93,
        "payload": {"known": false, "person_name": null}
      }
    """
    url = settings.AI_SERVER_URL.rstrip("/") + settings.AI_FACE_ENDPOINT

    files = {
        "frame": (getattr(image_file, "name", "frame.jpg"), image_file, getattr(image_file, "content_type", "image/jpeg"))
    }
    data = {"patient_id": patient_id}

    try:
        resp = requests.post(url, files=files, data=data, timeout=10)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        raise AIClientError(f"AI server request failed: {str(e)}")


def track_person(image_file, patient_id: str) -> dict:
    """
    Sends multipart image to AI server for person tracking.
    Returns face embedding and bounding box information.
    Expected JSON shape:
      {
        "status": "success",
        "face_detected": true,
        "embedding": [0.1, 0.2, ...],
        "bbox": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4}
      }
    """
    url = settings.AI_SERVER_URL.rstrip("/") + "/track-person"

    files = {
        "frame": (getattr(image_file, "name", "frame.jpg"), image_file, getattr(image_file, "content_type", "image/jpeg"))
    }
    data = {"patient_id": patient_id}

    try:
        resp = requests.post(url, files=files, data=data, timeout=10)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        raise AIClientError(f"AI server tracking request failed: {str(e)}")
