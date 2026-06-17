"""
demo_activity_accel.py — Activity recognition + accelerometer fall detection demo.

Run on the Pi:
    export CAMERA_URL="http://172.20.10.7:8080/video"
    python demo_activity_accel.py

Then open http://<pi-ip>:5000 in your browser to see the live annotated feed.
"""
import os
import sys
import threading
import time
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch
from flask import Flask, Response

# ---------------------------------------------------------------------------
# Path setup — must come before any perception imports
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent
AR_DIR    = REPO_ROOT / "perception" / "activity_recognition"
SK_DIR    = REPO_ROOT / "SkateFormer"

sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(AR_DIR))

from perception.activity_recognition.config import (
    CAMERA_INDEX, FRAME_WIDTH, FRAME_HEIGHT, TARGET_FPS,
    ACCEL_ENABLED,
)

FALL_PERSIST_FRAMES = 10

# Demo-mode thresholds — patch accelerometer module globals so the loop picks them up.
# Production values: ACCEL_STANDALONE_G=4.0, ACCEL_IMPACT_THRESHOLD_G=2.5
import perception.activity_recognition.accelerometer as _accel_mod
_accel_mod.ACCEL_STANDALONE_G         = 2.0
_accel_mod.ACCEL_IMPACT_THRESHOLD_G   = 1.8
_accel_mod.ACCEL_FREEFALL_THRESHOLD_G = 0.7

from perception.activity_recognition.pose_estimator import PoseEstimator
from perception.activity_recognition.accelerometer import AccelerometerReader

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CLASS_NAMES       = ["EAT", "DRINK", "SLEEP", "FALL", "WALK", "SIT", "STAND", "USE_PHONE"]
LABEL_COLORS = {
    "EAT":       (0,   200, 255),
    "DRINK":     (0,   200, 255),
    "SLEEP":     (200, 200,   0),
    "FALL":      (0,     0, 255),
    "WALK":      (0,   255,   0),
    "SIT":       (255, 180,   0),
    "STAND":     (255, 255,   0),
    "USE_PHONE": (180,   0, 255),
}
CHECKPOINT        = AR_DIR / "work_dir" / "sava_8class" / "best_8class.pt"
FALL_IDX          = CLASS_NAMES.index("FALL")
SMOOTH_WINDOW     = 15
FALL_PROB_SECS    = 3
FALL_SOFT_THRESH  = 0.30
CONFIDENCE_THRESH = 0.65
PRINT_INTERVAL    = 1.0
STREAM_PORT       = 5000

# ---------------------------------------------------------------------------
# Shared state between processing thread and Flask stream thread
# ---------------------------------------------------------------------------
_frame_lock   = threading.Lock()
_latest_frame = None   # latest annotated JPEG bytes


# ---------------------------------------------------------------------------
# Model helpers
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
# Frame annotation
# ---------------------------------------------------------------------------

def _annotate(frame: np.ndarray, label: str, conf: float,
               accel_mag: float, fall_note: str) -> np.ndarray:
    h, w = frame.shape[:2]

    # Activity label (top-left)
    color = LABEL_COLORS.get(label, (255, 255, 255)) if label else (180, 180, 180)
    text  = f"{label}  {conf:.0%}" if label else "Detecting..."
    cv2.putText(frame, text, (15, 45),
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 0), 4)
    cv2.putText(frame, text, (15, 45),
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, color, 2)

    # Accelerometer magnitude (bottom-left)
    accel_text = f"|a| = {accel_mag:.3f} g"
    cv2.putText(frame, accel_text, (15, h - 15),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (200, 200, 200), 2)

    # Fall alert (centre, large red)
    if fall_note:
        trigger = fall_note.split("[")[1].rstrip("]").split()[0] if "[" in fall_note else ""
        alert   = f"⚠ FALL DETECTED  [{trigger}]"
        (tw, th), _ = cv2.getTextSize(alert, cv2.FONT_HERSHEY_SIMPLEX, 1.1, 3)
        cv2.putText(frame, alert, ((w - tw) // 2, h // 2),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 0, 0), 5)
        cv2.putText(frame, alert, ((w - tw) // 2, h // 2),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 0, 255), 3)

    return frame


# ---------------------------------------------------------------------------
# Flask MJPEG server
# ---------------------------------------------------------------------------
_app = Flask(__name__)


@_app.route("/")
def index():
    return (
        "<html><body style='margin:0;background:#000'>"
        "<img src='/video' style='width:100%;height:100vh;object-fit:contain'>"
        "</body></html>"
    )


@_app.route("/video")
def video():
    def gen():
        global _latest_frame
        while True:
            with _frame_lock:
                jpg = _latest_frame
            if jpg is not None:
                yield (b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + jpg + b"\r\n")
            time.sleep(1 / TARGET_FPS)
    return Response(gen(), mimetype="multipart/x-mixed-replace; boundary=frame")


# ---------------------------------------------------------------------------
# Processing loop (runs in main thread)
# ---------------------------------------------------------------------------

def main():
    global _latest_frame
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

    model = _load_model(device)
    pose  = PoseEstimator()

    url = os.environ.get("CAMERA_URL", "") or CAMERA_INDEX
    cap = cv2.VideoCapture(url)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open camera: {url}")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    print(f"✅ Camera opened: {url}")

    # Start Flask in background thread
    flask_thread = threading.Thread(
        target=lambda: _app.run(host="0.0.0.0", port=STREAM_PORT, threaded=True),
        daemon=True,
    )
    flask_thread.start()
    print(f"✅ Stream live at  http://<pi-ip>:{STREAM_PORT}")
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

            # Pose estimation with skeleton drawing
            frame, _ = pose.extract(frame, draw=True)

            # Activity recognition
            if model is not None:
                sk_input = pose.get_skateformer_input()
                if sk_input is not None:
                    probs = _predict(model, device, sk_input)
                    probs_buffer.append(probs)
                    avg       = np.mean(probs_buffer, axis=0)
                    best_idx  = int(np.argmax(avg))
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

            # 3-tier fall fusion
            accel_mag    = accel.magnitude       if accel else 0.0
            accel_impact = accel.recent_impact   if accel else False
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

            # Annotate and encode frame for streaming
            frame = _annotate(frame, last_pred, last_conf, accel_mag, fall_note)
            ok, jpg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
            if ok:
                with _frame_lock:
                    _latest_frame = jpg.tobytes()

            # Console print once per second
            now = time.time()
            if now - last_print_t >= PRINT_INTERVAL:
                elapsed = now - start_t
                act_str = last_pred if last_pred else "---"
                print(f"{elapsed:8.1f}  {act_str:<12}  {last_conf:5.2f}  {accel_mag:7.3f}  {fall_note}")
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
