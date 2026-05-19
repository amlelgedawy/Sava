import cv2
import numpy as np
import mediapipe as mp


class PainDetector:
    """
    Estimates the PSPI (Prkachin and Solomon Pain Intensity) score from
    facial landmarks using MediaPipe Face Mesh.

    PSPI = AU4 + max(AU6, AU7) + max(AU9, AU10) + AU43
    Range: 0 (no pain) → 16 (severe pain). Clinical threshold: ≥ 6.

    Each AU is approximated from landmark geometry, normalised by face width,
    so the score is invariant to the patient's distance from the camera.
    """

    # EAR landmark indices (p1, p2, p3, p4, p5, p6)
    _LEFT_EYE  = [33,  160, 158, 133, 153, 144]
    _RIGHT_EYE = [362, 385, 387, 263, 373, 380]

    # Brow and eye-top landmarks for AU4
    _L_INNER_BROW = 107
    _R_INNER_BROW = 336
    _L_EYE_TOP    = 159
    _R_EYE_TOP    = 386

    # Nose bridge and upper lip for AU9/AU10
    _NOSE_BRIDGE = 6
    _UPPER_LIP   = 0

    # Face-width reference points (left/right tragus approximation)
    _FACE_L = 234
    _FACE_R = 454

    def __init__(self):
        self._face_mesh = mp.solutions.face_mesh.FaceMesh(
            max_num_faces=1,
            refine_landmarks=False,
            min_detection_confidence=0.3,
            min_tracking_confidence=0.3,
        )

    def process(self, frame: np.ndarray) -> tuple[float, np.ndarray | None]:
        """
        Run Face Mesh on frame.
        Returns (pspi_score, face_crop) — face_crop is None if no face found.
        """
        rgb     = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self._face_mesh.process(rgb)

        if not results.multi_face_landmarks:
            return 0.0, None

        lm     = results.multi_face_landmarks[0].landmark
        face_w = self._face_width(lm)

        au4        = self._au4(lm, face_w)
        au6, au7   = self._au6_au7(lm)
        au9, au10  = self._au9_au10(lm, face_w)
        au43       = self._au43(lm)

        pspi = float(np.clip(au4 + max(au6, au7) + max(au9, au10) + au43, 0.0, 16.0))

        # Debug — print every 30 frames so we can verify AU values and tune thresholds
        self._dbg_count = getattr(self, "_dbg_count", 0) + 1
        if self._dbg_count % 30 == 0:
            nose_lip_raw = float(np.linalg.norm(
                self._pt(lm, self._NOSE_BRIDGE) - self._pt(lm, self._UPPER_LIP)
            ) / face_w)
            brow_eye_raw = float((
                np.linalg.norm(self._pt(lm, self._L_INNER_BROW) - self._pt(lm, self._L_EYE_TOP)) +
                np.linalg.norm(self._pt(lm, self._R_INNER_BROW) - self._pt(lm, self._R_EYE_TOP))
            ) / 2 / face_w)
            avg_ear = (self._ear(lm, self._LEFT_EYE) + self._ear(lm, self._RIGHT_EYE)) / 2
            print(f"[PainDetector] face_w={face_w:.3f} | brow_eye={brow_eye_raw:.3f} AU4={au4:.2f} | "
                  f"EAR={avg_ear:.3f} AU6={au6:.2f} | nose_lip={nose_lip_raw:.3f} AU9={au9:.2f} | "
                  f"AU43={au43:.2f} | PSPI={pspi:.2f}")

        crop = self._face_crop(frame, lm)
        return pspi, crop

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _pt(self, lm, idx):
        return np.array([lm[idx].x, lm[idx].y])

    def _face_width(self, lm):
        return float(np.linalg.norm(self._pt(lm, self._FACE_R) - self._pt(lm, self._FACE_L))) + 1e-6

    def _ear(self, lm, indices):
        """Eye Aspect Ratio from 6 landmark indices."""
        p = [self._pt(lm, i) for i in indices]
        vertical   = (np.linalg.norm(p[1] - p[5]) + np.linalg.norm(p[2] - p[4])) / 2.0
        horizontal = np.linalg.norm(p[0] - p[3]) + 1e-6
        return float(vertical / horizontal)

    def _au4(self, lm, face_w):
        """Brow lowering: normalised brow-to-eye distance decreases when brow furrows."""
        l = np.linalg.norm(self._pt(lm, self._L_INNER_BROW) - self._pt(lm, self._L_EYE_TOP)) / face_w
        r = np.linalg.norm(self._pt(lm, self._R_INNER_BROW) - self._pt(lm, self._R_EYE_TOP)) / face_w
        dist = (l + r) / 2.0
        # face-crop calibration: 0.09 → relaxed (AU4=0),  0.03 → furrowed (AU4=4)
        return float(np.clip((0.09 - dist) / 0.06 * 4.0, 0.0, 4.0))

    def _au6_au7(self, lm):
        """Cheek raiser / lid tightener: eyes narrow → EAR drops."""
        avg_ear = (self._ear(lm, self._LEFT_EYE) + self._ear(lm, self._RIGHT_EYE)) / 2.0
        # 0.30 → open (intensity=0),  0.15 → narrowed (intensity=4)
        intensity = float(np.clip((0.30 - avg_ear) / 0.15 * 4.0, 0.0, 4.0))
        return intensity, intensity

    def _au9_au10(self, lm, face_w):
        """Nose wrinkler / upper lip raiser: nose bridge moves toward lip."""
        dist = np.linalg.norm(
            self._pt(lm, self._NOSE_BRIDGE) - self._pt(lm, self._UPPER_LIP)
        ) / face_w
        # face-crop calibration: 0.46 → relaxed (intensity=0),  0.30 → wrinkled (intensity=4)
        intensity = float(np.clip((0.46 - dist) / 0.16 * 4.0, 0.0, 4.0))
        return intensity, intensity

    def _au43(self, lm):
        """Eye closure: EAR near zero → AU43 near 4."""
        avg_ear = (self._ear(lm, self._LEFT_EYE) + self._ear(lm, self._RIGHT_EYE)) / 2.0
        # 0.25 → fully open (AU43=0),  0.0 → fully closed (AU43=4)
        return float(np.clip((1.0 - avg_ear / 0.25) * 4.0, 0.0, 4.0))

    def _face_crop(self, frame: np.ndarray, lm) -> np.ndarray | None:
        """Crop the face region from the frame using landmark bounding box + 15% padding."""
        h, w = frame.shape[:2]
        xs = [lm[i].x * w for i in range(len(lm))]
        ys = [lm[i].y * h for i in range(len(lm))]
        pad = int((max(xs) - min(xs)) * 0.15)
        x1  = max(0, int(min(xs)) - pad)
        y1  = max(0, int(min(ys)) - pad)
        x2  = min(w, int(max(xs)) + pad)
        y2  = min(h, int(max(ys)) + pad)
        if x2 <= x1 or y2 <= y1:
            return None
        return frame[y1:y2, x1:x2]

    def close(self):
        self._face_mesh.close()
