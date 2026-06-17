"""
demo_activity_accel.py — Activity recognition + accelerometer fall detection demo.

Run on the Pi:
    export CAMERA_URL="http://172.20.10.7:8080/video"
    python demo_activity_accel.py
"""
import os
import sys
import time
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch

# ---------------------------------------------------------------------------
# Path setup — must come before any perception imports
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent
AR_DIR    = REPO_ROOT / "perception" / "activity_recognition"
SK_DIR    = REPO_ROOT / "SkateFormer"

sys.path.insert(0, str(REPO_ROOT))   # for perception.* package imports
sys.path.insert(0, str(AR_DIR))      # for data_preprocessing (used by pose_estimator)

from perception.activity_recognition.config import (
    CAMERA_INDEX, FRAME_WIDTH, FRAME_HEIGHT, TARGET_FPS,
    ACCEL_ENABLED, FALL_PERSIST_FRAMES,
)
from perception.activity_recognition.pose_estimator import PoseEstimator
from perception.activity_recognition.accelerometer import AccelerometerReader

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CLASS_NAMES       = ["EAT", "DRINK", "SLEEP", "FALL", "WALK", "SIT", "STAND", "USE_PHONE"]
CHECKPOINT        = AR_DIR / "work_dir" / "sava_8class" / "best_8class.pt"
FALL_IDX          = CLASS_NAMES.index("FALL")
SMOOTH_WINDOW     = 15     # frames to average predictions over
FALL_PROB_SECS    = 3      # rolling window length for FALL class probability
FALL_SOFT_THRESH  = 0.30   # min average FALL prob required for soft-fusion trigger
CONFIDENCE_THRESH = 0.65   # min overall confidence to report an activity label
PRINT_INTERVAL    = 1.0    # seconds between console output lines

# ---------------------------------------------------------------------------
# Model helpers (copied from camera.py to avoid its heavy import chain)
# ---------------------------------------------------------------------------

def _load_model(device: str):
    if not CHECKPOINT.exists():
        print(f"  Checkpoint not found: {CHECKPOINT}")
        print("   Running accelerometer-only fall detection.")
        return None
    if str(SK_DIR) not in sys.path:
        sys.path.insert(0, str(SK_DIR))
    try:
        from model.SkateFormer import SkateFormer
    except ImportError:
        print("  SkateFormer not importable. Running accelerometer-only.")
        return None
    model = SkateFormer(
        in_channels=3, depths=(2, 2, 2, 2), channels=(96, 192, 192, 192),
        num_classes=len(CLASS_NAMES), embed_dim=96, num_people=2,
        num_frames=64, num_points=24, kernel_size=7, num_heads=32,
        type_1_size=(8, 8), type_2_size=(8, 12),
        type_3_size=(8, 8), type_4_size=(8, 12),
        attn_drop=0.5, head_drop=0.0, rel=True, drop_path=0.2,
        mlp_ratio=4.0, index_t=True,
    ).to(device)
    ckpt = torch.load(str(CHECKPOINT), map_location=device)
    model.load_state_dict(ckpt["model"], strict=True)
    model.eval()
    print(f"  Loaded SkateFormer from {CHECKPOINT.name}")
    return model


@torch.no_grad()
def _predict(model, device: str, sk_input: np.ndarray) -> np.ndarray:
    x   = torch.from_numpy(sk_input).float().unsqueeze(0).to(device)
    idx = torch.arange(64, dtype=torch.long).unsqueeze(0).to(device)
    return torch.softmax(model(x, idx), dim=1)[0].cpu().numpy()


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main():
    device = "cpu"

    # Accelerometer
    accel = None
    if ACCEL_ENABLED:
        try:
            accel = AccelerometerReader()
            accel.start()
            print("✅ Accelerometer (MPU-6050) connected.")
        except Exception as exc:
            print(f"⚠  Accelerometer not available: {exc}")

    # Activity recognition model
    model = _load_model(device)

    # Pose estimator
    pose = PoseEstimator()

    # Camera stream
    url = os.environ.get("CAMERA_URL", "") or CAMERA_INDEX
    cap = cv2.VideoCapture(url)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open camera: {url}")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    print(f"✅ Camera opened: {url}")
    print("   Ctrl+C to stop.\n")
    print(f"{'Time(s)':>8}  {'Activity':<12}  {'Conf':>5}  {'|a|(g)':>7}  Note")
    print("-" * 58)

    probs_buffer     = deque(maxlen=SMOOTH_WINDOW)
    fall_prob_window = deque(maxlen=int(TARGET_FPS * FALL_PROB_SECS))
    fall_consec      = 0
    last_pred        = None
    last_conf        = 0.0
    last_print_t     = 0.0
    start_t          = time.time()

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.05)
                continue

            frame = cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT))

            # Pose estimation (no drawing — headless)
            _, _ = pose.extract(frame, draw=False)

            # Activity recognition
            if model is not None:
                sk_input = pose.get_skateformer_input()
                if sk_input is not None:
                    probs = _predict(model, device, sk_input)
                    probs_buffer.append(probs)
                    avg      = np.mean(probs_buffer, axis=0)
                    best_idx = int(np.argmax(avg))
                    best_conf = float(avg[best_idx])

                    fall_prob_window.append(float(probs[FALL_IDX]))

                    if best_conf >= CONFIDENCE_THRESH:
                        last_pred = CLASS_NAMES[best_idx]
                        last_conf = best_conf
                    else:
                        last_pred = None
                        last_conf = best_conf

            # Fall consecutive counter
            if last_pred == "FALL":
                fall_consec += 1
            else:
                fall_consec = 0

            # --- 3-tier accelerometer + camera fall fusion ---
            accel_mag   = accel.magnitude       if accel else 0.0
            accel_impact = accel.recent_impact  if accel else False
            accel_alone  = accel.standalone_fall if accel else False

            recent_fall_score = float(np.mean(fall_prob_window)) if fall_prob_window else 0.0
            camera_fall_soft  = recent_fall_score >= FALL_SOFT_THRESH
            camera_fall_hard  = fall_consec >= FALL_PERSIST_FRAMES

            if accel_alone:
                fall_note = f"FALL [accel-alone  |a|={accel_mag:.2f}g]"
            elif accel_impact and camera_fall_soft:
                fall_note = f"FALL [soft-fusion  score={recent_fall_score:.2f}  |a|={accel_mag:.2f}g]"
            elif camera_fall_hard and accel_impact:
                fall_note = f"FALL [hard-fusion  frames={fall_consec}  |a|={accel_mag:.2f}g]"
            else:
                fall_note = ""

            # Console print once per second
            now = time.time()
            if now - last_print_t >= PRINT_INTERVAL:
                elapsed  = now - start_t
                act_str  = last_pred if last_pred else "---"
                note     = fall_note if fall_note else ""
                print(f"{elapsed:8.1f}  {act_str:<12}  {last_conf:5.2f}  {accel_mag:7.3f}  {note}")
                last_print_t = now

    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        cap.release()
        pose.close()
        if accel:
            accel.stop()


if __name__ == "__main__":
    main()
