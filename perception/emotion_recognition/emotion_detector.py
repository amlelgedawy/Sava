import cv2
import numpy as np
from hsemotion_onnx.facial_emotions import HSEmotionRecognizer


class EmotionDetector:
    def __init__(self, device: str = "cpu"):
        self._model = HSEmotionRecognizer(model_name="enet_b0_8_best_afew")

    def detect(self, face_crop: np.ndarray) -> tuple[str, float] | None:
        """Return (emotion_label, confidence) or None if face_crop is invalid."""
        if face_crop is None or face_crop.size == 0:
            return None
        h, w = face_crop.shape[:2]
        if h < 48 or w < 48:
            face_crop = cv2.resize(face_crop, (224, 224))
        try:
            face_rgb = cv2.cvtColor(face_crop, cv2.COLOR_BGR2RGB)
            emotion, scores = self._model.predict_emotions(face_rgb, logits=False)
            return emotion, float(max(scores))
        except Exception as e:
            print(f"[EmotionDetector] {e}")
            return None
