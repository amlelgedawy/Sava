"""
Standalone activity recognition test — no Django, no face recognition, no object detection.
Runs: YOLO person detection → MediaPipe pose → SkateFormer 8-class activity recognition.
"""
import sys
import time
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch

# ── SkateFormer ──────────────────────────────────────────────────────────────
SKATEFORMER_DIR = str(Path(__file__).parent / "SkateFormer")
CHECKPOINT      = Path(__file__).parent / "perception/activity_recognition/work_dir/sava_8class/best_8class.pt"
CLASS_NAMES     = ["EAT", "DRINK", "SLEEP", "FALL", "WALK", "SIT", "STAND", "USE_PHONE"]
LABEL_COLORS    = {
    "EAT":       (0, 200, 255),
    "DRINK":     (0, 200, 255),
    "SLEEP":     (200, 200, 0),
    "FALL":      (0, 0, 255),
    "WALK":      (0, 255, 0),
    "SIT":       (255, 180, 0),
    "STAND":     (255, 255, 0),
    "USE_PHONE": (180, 0, 255),
}

# ── Camera / inference settings ───────────────────────────────────────────────
FRAME_W          = 640
FRAME_H          = 480
TARGET_FPS       = 15
SMOOTH_WINDOW    = 15
CONF_THRESH      = 0.75
FALL_THRESH      = 0.75
FALL_PERSIST     = 10    # consecutive FALL frames before alerting
DRINK_PERSIST    = 8     # consecutive DRINK frames before showing (filters brief hand-raises)
DRINK_EAT_MARGIN = 0.15  # if DRINK beats EAT by less than this, show EAT instead


def load_model(device):
    if not CHECKPOINT.exists():
        print(f"Checkpoint not found: {CHECKPOINT}")
        return None
    if SKATEFORMER_DIR not in sys.path:
        sys.path.insert(0, SKATEFORMER_DIR)
    from model.SkateFormer import SkateFormer
    model = SkateFormer(
        in_channels=3, depths=(2,2,2,2), channels=(96,192,192,192),
        num_classes=len(CLASS_NAMES), embed_dim=96, num_people=2,
        num_frames=64, num_points=24, kernel_size=7, num_heads=32,
        type_1_size=(8,8), type_2_size=(8,12), type_3_size=(8,8), type_4_size=(8,12),
        attn_drop=0.5, head_drop=0.0, rel=True, drop_path=0.2, mlp_ratio=4.0, index_t=True
    ).to(device)
    ckpt = torch.load(str(CHECKPOINT), map_location=device)
    model.load_state_dict(ckpt["model"], strict=True)
    model.eval()
    print(f"Loaded 8-class SkateFormer from {CHECKPOINT}")
    return model


@torch.no_grad()
def predict(model, device, sk_input):
    x       = torch.from_numpy(sk_input).float().unsqueeze(0).to(device)
    index_t = torch.arange(64, dtype=torch.long).unsqueeze(0).to(device)
    probs   = torch.softmax(model(x, index_t), dim=1)[0].cpu().numpy()
    return probs


def main():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")
    torch.cuda.empty_cache()

    from ultralytics import YOLO
    from perception.activity_recognition.pose_estimator import PoseEstimator

    yolo     = YOLO(str(Path(__file__).parent / "yolov8n.pt"))
    model    = load_model(device)
    pose_est = PoseEstimator()

    # Windows needs CAP_DSHOW for webcam
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(0)   # fallback without backend flag
    if not cap.isOpened():
        raise RuntimeError("Cannot open camera")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  FRAME_W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_H)
    print("Camera started. Press 'q' to quit.")

    probs_buffer = deque(maxlen=SMOOTH_WINDOW)
    last_pred    = None
    last_conf    = 0.0
    fall_consec  = 0
    drink_consec = 0
    prev_time    = 0.0

    while True:
        ret, frame = cap.read()
        if not ret:
            print("Failed to grab frame.")
            break

        frame = cv2.resize(frame, (FRAME_W, FRAME_H))

        # Person detection (CPU)
        results   = yolo(frame, classes=[0], verbose=False, device='cpu')
        frame     = results[0].plot()

        # Pose estimation
        frame, _ = pose_est.extract(frame, draw=True)

        # Activity recognition
        if model is not None:
            sk_input = pose_est.get_skateformer_input()
            if sk_input is not None:
                probs     = predict(model, device, sk_input)
                probs_buffer.append(probs)
                avg       = np.mean(probs_buffer, axis=0)
                best_id   = int(np.argmax(avg))
                best_conf = float(avg[best_id])
                pred_name = CLASS_NAMES[best_id]
                thresh    = FALL_THRESH if pred_name == "FALL" else CONF_THRESH
                if best_conf >= thresh:
                    last_pred = pred_name
                    last_conf = best_conf
                else:
                    last_pred = None
                    last_conf = best_conf

                # Option 3 — margin check: if DRINK barely beats EAT, prefer EAT
                if last_pred == "DRINK":
                    drink_prob = float(avg[CLASS_NAMES.index("DRINK")])
                    eat_prob   = float(avg[CLASS_NAMES.index("EAT")])
                    if drink_prob - eat_prob < DRINK_EAT_MARGIN:
                        last_pred = "EAT"
                        last_conf = eat_prob

        # Option 2 — persistence gate: DRINK must hold for N frames before showing
        if last_pred == "DRINK":
            drink_consec += 1
            if drink_consec < DRINK_PERSIST:
                last_pred = None   # suppress until sustained
        else:
            drink_consec = 0

        if last_pred == "FALL":
            fall_consec += 1
        else:
            fall_consec = 0

        # FPS cap
        now = time.time()
        if now - prev_time < 1.0 / TARGET_FPS:
            continue
        fps       = 1.0 / (now - prev_time) if now > prev_time else 0
        prev_time = now

        # Overlay
        cv2.putText(frame, f"FPS: {int(fps)}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255,255,255), 2)

        if model is not None:
            if len(probs_buffer) < SMOOTH_WINDOW:
                cv2.putText(frame, f"Collecting... ({len(probs_buffer)}/{SMOOTH_WINDOW})",
                            (10, 65), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (180,180,180), 2)
            elif last_pred:
                color = LABEL_COLORS.get(last_pred, (0,255,0))
                cv2.putText(frame, f"{last_pred}  ({last_conf*100:.1f}%)",
                            (10, 65), cv2.FONT_HERSHEY_SIMPLEX, 1.0, color, 2)
            else:
                cv2.putText(frame, f"Uncertain  ({last_conf*100:.1f}%)",
                            (10, 65), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (180,180,180), 2)

        if fall_consec >= FALL_PERSIST:
            cv2.putText(frame, "FALL DETECTED", (10, 110),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0,0,255), 3)

        cv2.imshow("SAVA - Activity Recognition Test", frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    pose_est.close()
    cv2.destroyAllWindows()
    print("Stopped.")


if __name__ == "__main__":
    main()
