import requests
from django.conf import settings

class AIClientError(Exception):
    pass

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
