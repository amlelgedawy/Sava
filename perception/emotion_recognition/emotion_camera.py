import cv2

from .emotion_detector import EmotionDetector
from .pain_detector import PainDetector
from perception.activity_recognition.config import EMOTION_CAMERA_INDEX, EMOTION_FRAME_INTERVAL


def run_emotion_camera(shared_state: dict, device: str) -> None:
    """
    Dedicated capture loop for the face-level camera (Camera 2).
    Runs as a daemon thread started from main.py.

    Every frame  : MediaPipe Face Mesh → PSPI pain score → shared_state["pspi"]
    Every N frames: HSEmotion → emotion label + confidence → shared_state["emotion"]
    """
    emotion_det = EmotionDetector(device)
    pain_det    = PainDetector()

    cap = cv2.VideoCapture(EMOTION_CAMERA_INDEX, cv2.CAP_DSHOW)
    if not cap.isOpened():
        print(f"⚠  Emotion camera (index {EMOTION_CAMERA_INDEX}) not found — "
              "emotion/pain detection disabled.")
        pain_det.close()
        return

    print(f"✅ Emotion camera (index {EMOTION_CAMERA_INDEX}) started.")
    frame_count = 0

    while not shared_state.get("stop", False):
        ret, frame = cap.read()
        if not ret:
            continue

        frame_count += 1

        # Always compute PSPI (Face Mesh runs every frame — fast)
        pspi, face_crop = pain_det.process(frame)
        with shared_state["lock"]:
            shared_state["pspi"] = pspi

        # Emotion inference every N frames to protect FPS budget
        if frame_count % EMOTION_FRAME_INTERVAL == 0 and face_crop is not None:
            result = emotion_det.detect(face_crop)
            if result is not None:
                emotion, conf = result
                with shared_state["lock"]:
                    shared_state["emotion"]      = emotion
                    shared_state["emotion_conf"] = conf

    cap.release()
    pain_det.close()
    print("🛑 Emotion camera stopped.")
