"""
Standalone copy of DangerousObjectDetector for Activity Recognition server.
Original: perception/object_detection/detector.py
"""

import os
import time
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO


# Configuration
_PROJECT_ROOT = Path(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_MODEL_PATH = str(_PROJECT_ROOT.parent.parent / "Object detection" / "models" / "sava_dangerous_best.pt")

OBJECT_DETECTION_MODEL_PATH = os.environ.get("OBJECT_DETECTION_MODEL_PATH", DEFAULT_MODEL_PATH)
OBJECT_DETECTION_CONF = float(os.environ.get("OBJECT_DETECTION_CONF", "0.54"))
OBJECT_DETECTION_INTERVAL = float(os.environ.get("OBJECT_DETECTION_INTERVAL", "2.0"))

DANGER_LEVELS = {
    "knife":       "HIGH",
    "gun":         "HIGH",
    "syringe":     "HIGH",
    "scissors":    "MEDIUM",
    "razor":       "HIGH",
    "pill_bottle": "MEDIUM",
    "bottle":      "LOW",
}

DANGER_COLORS = {
    "HIGH":   (0, 0, 255),
    "MEDIUM": (0, 165, 255),
    "LOW":    (0, 255, 255),
}


class DangerousObjectDetector:
    def __init__(self, model_path: str = None, conf: float = None, interval: float = None):
        self._model_path = model_path or OBJECT_DETECTION_MODEL_PATH
        self._conf = conf or OBJECT_DETECTION_CONF
        self._interval = interval or OBJECT_DETECTION_INTERVAL
        self._last_run = 0.0
        self._last_detections = []
        self._model = None

    def load(self):
        if not Path(self._model_path).exists():
            print(f"  [ObjectDetection] Model not found: {self._model_path}")
            print("   Object detection will be disabled.")
            return False

        self._model = YOLO(self._model_path)
        print(f"  [ObjectDetection] Model loaded: {self._model_path}")
        print(f"  [ObjectDetection] Classes: {self._model.names}")
        print(f"  [ObjectDetection] Confidence threshold: {self._conf}")
        print(f"  [ObjectDetection] Detection interval: {self._interval}s")
        return True

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    @property
    def last_detections(self) -> list:
        return self._last_detections

    def detect(self, frame: np.ndarray) -> list:
        if not self.is_loaded:
            return []

        now = time.time()
        if now - self._last_run < self._interval:
            return self._last_detections

        self._last_run = now

        results = self._model.predict(
            source=frame,
            conf=self._conf,
            verbose=False,
        )

        h, w = frame.shape[:2]
        detections = []

        for box in results[0].boxes:
            cls_id = int(box.cls[0])
            confidence = float(box.conf[0])
            label = self._model.names[cls_id].lower()
            danger_level = DANGER_LEVELS.get(label, "LOW")

            x1, y1, x2, y2 = box.xyxy[0].tolist()
            detections.append({
                "label": label,
                "confidence": round(confidence, 3),
                "danger_level": danger_level,
                "is_dangerous": True,
                "box_px": (int(x1), int(y1), int(x2), int(y2)),
                "box_norm": {
                    "x1": round(x1 / w, 4),
                    "y1": round(y1 / h, 4),
                    "x2": round(x2 / w, 4),
                    "y2": round(y2 / h, 4),
                },
            })

        self._last_detections = detections
        return detections

    def draw_detections(self, frame: np.ndarray) -> np.ndarray:
        for det in self._last_detections:
            x1, y1, x2, y2 = det["box_px"]
            level = det["danger_level"]
            color = DANGER_COLORS.get(level, (0, 255, 255))
            label_text = f"{det['label']} {det['confidence']:.0%} [{level}]"

            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            (tw, th), _ = cv2.getTextSize(label_text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1)
            cv2.rectangle(frame, (x1, y1 - th - 8), (x1 + tw + 4, y1), color, -1)
            cv2.putText(frame, label_text, (x1 + 2, y1 - 4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

        return frame
