"""
detector.py
-----------
Dangerous object detection module for the SAVA camera pipeline.
Loads the trained YOLOv8 model (sava_dangerous_best.pt) and runs inference
on camera frames at a configurable interval.

Classes: knife, scissors, gun, syringe, bottle, pill_bottle, razor
"""

import os
import time
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO


# ── Configuration ─────────────────────────────────────────────────────────────

# Path to the trained dangerous object detection model
_PROJECT_ROOT = Path(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DEFAULT_MODEL_PATH = str(_PROJECT_ROOT / "Object detection" / "models" / "sava_dangerous_best.pt")

OBJECT_DETECTION_MODEL_PATH = os.environ.get("OBJECT_DETECTION_MODEL_PATH", DEFAULT_MODEL_PATH)
OBJECT_DETECTION_CONF = float(os.environ.get("OBJECT_DETECTION_CONF", "0.75"))

# Run object detection every N seconds (not every frame — too expensive)
OBJECT_DETECTION_INTERVAL = float(os.environ.get("OBJECT_DETECTION_INTERVAL", "2.0"))

# Danger level mapping per class name
DANGER_LEVELS = {
    "knife":       "HIGH",
    "gun":         "HIGH",
    "syringe":     "HIGH",
    "scissors":    "MEDIUM",
    "razor":       "HIGH",
    "pill_bottle": "MEDIUM",
    "bottle":      "LOW",
}

# Overlay colours per danger level
DANGER_COLORS = {
    "HIGH":   (0, 0, 255),    # Red
    "MEDIUM": (0, 165, 255),  # Orange
    "LOW":    (0, 255, 255),  # Yellow
}


class DangerousObjectDetector:
    """
    Wraps the dangerous object YOLO model for use in the camera pipeline.
    Runs detection at a configurable interval and caches the last results
    for overlay rendering between detection cycles.
    """

    def __init__(self, model_path: str = None, conf: float = None, interval: float = None):
        self._model_path = model_path or OBJECT_DETECTION_MODEL_PATH
        self._conf = conf or OBJECT_DETECTION_CONF
        self._interval = interval or OBJECT_DETECTION_INTERVAL
        self._last_run = 0.0
        self._last_detections = []  # cached results for overlay
        self._model = None

    def load(self):
        """Load the YOLO model. Call once at startup."""
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
        """Return the most recent detection results (for sending events)."""
        return self._last_detections

    def detect(self, frame: np.ndarray) -> list:
        """
        Run object detection on the frame if the interval has elapsed.
        Returns list of detections (may be cached from last run).

        Each detection dict:
          {
            "label": str,
            "confidence": float,
            "danger_level": str,
            "is_dangerous": bool,
            "box_px": (x1, y1, x2, y2),  # pixel coords
            "box_norm": {"x1": float, "y1": float, "x2": float, "y2": float},
          }
        """
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
            device='cpu',
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
        """Draw cached detections on the frame for display."""
        for det in self._last_detections:
            x1, y1, x2, y2 = det["box_px"]
            level = det["danger_level"]
            color = DANGER_COLORS.get(level, (0, 255, 255))
            label_text = f"{det['label']} {det['confidence']:.0%} [{level}]"

            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            # Label background
            (tw, th), _ = cv2.getTextSize(label_text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1)
            cv2.rectangle(frame, (x1, y1 - th - 8), (x1 + tw + 4, y1), color, -1)
            cv2.putText(frame, label_text, (x1 + 2, y1 - 4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

        return frame
