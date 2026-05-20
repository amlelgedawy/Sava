import numpy as np
import mediapipe as mp

from data_preprocessing.convert_to_ntu import mediapipe_to_ntu, normalize_skeleton

# SkateFormer partition joint order: maps NTU 25-joint → 24-joint
# Matches feeder_ntu.py `new_idx` when partition=True
NEW_IDX_24 = np.array([
    6, 7, 21, 22,       # right_arm
    10, 11, 23, 24,     # left_arm
    12, 13, 14, 15,     # right_leg
    16, 17, 18, 19,     # left_leg
    4, 8, 5, 9,         # h_torso
    1, 2, 0, 3          # w_torso
], dtype=np.int64)

WINDOW_SIZE = 64


class PoseEstimator:
    """
    MediaPipe-based pose estimator with a 64-frame sliding window buffer.
    Produces SkateFormer-ready input tensors (C, T, V, M) = (3, 64, 24, 2).
    """

    def __init__(self):
        mp_pose = mp.solutions.pose
        self.mp_drawing = mp.solutions.drawing_utils
        self.pose = mp_pose.Pose(
            static_image_mode=False,
            model_complexity=1,
            enable_segmentation=False,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )
        self.POSE_CONNECTIONS = mp_pose.POSE_CONNECTIONS
        self._buffer = []  # list of (24, 3) frames

    def extract(self, frame, draw=True):
        """
        Process one BGR frame through MediaPipe.

        Returns:
            (annotated_frame, kps_33) where kps_33 is ndarray (33, 3) or None if no pose.
        """
        import cv2
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self.pose.process(rgb)

        kps_33 = None
        if results.pose_landmarks:
            if draw:
                self.mp_drawing.draw_landmarks(
                    frame, results.pose_landmarks, self.POSE_CONNECTIONS
                )
            kps_33 = np.array(
                [[lm.x, lm.y, lm.z] for lm in results.pose_landmarks.landmark],
                dtype=np.float32
            )  # (33, 3)
            self._add_to_buffer(kps_33)

        return frame, kps_33

    def _add_to_buffer(self, kps_33):
        """Convert MediaPipe 33-joint frame → NTU 24-joint, normalize, add to sliding window."""
        # (1, 33, 3) → (1, 25, 3) → (25, 3)
        ntu25 = mediapipe_to_ntu(kps_33[np.newaxis, ...])[0]  # (25, 3)
        ntu25 = normalize_skeleton(ntu25)                      # scale+position invariant
        ntu24 = ntu25[NEW_IDX_24, :]                           # (24, 3)
        self._buffer.append(ntu24)
        if len(self._buffer) > WINDOW_SIZE:
            self._buffer = self._buffer[-WINDOW_SIZE:]

    def get_skateformer_input(self):
        """
        Returns SkateFormer-ready ndarray (3, 64, 24, 2) when the window is full,
        otherwise returns None.
        """
        if len(self._buffer) < WINDOW_SIZE:
            return None

        window = np.stack(self._buffer, axis=0)  # (64, 24, 3)

        # Add second person (zeros)
        p2 = np.zeros_like(window)
        stacked = np.stack([window, p2], axis=-1)  # (64, 24, 3, 2)

        # (64, 24, 3, 2) → (3, 64, 24, 2)
        return stacked.transpose(2, 0, 1, 3).astype(np.float32)

    def close(self):
        self.pose.close()


# ---------------------------------------------------------------------------
# Module-level singleton + convenience function used by camera.py
# ---------------------------------------------------------------------------
_default_estimator = None


def estimate_pose(frame, draw=True):
    """
    Convenience wrapper around PoseEstimator for use in camera.py.
    Returns (annotated_frame, kps_33_or_None).
    """
    global _default_estimator
    if _default_estimator is None:
        _default_estimator = PoseEstimator()
    return _default_estimator.extract(frame, draw=draw)
