import sys
from pathlib import Path
import cv2
import numpy as np
import torch
import mediapipe as mp

from perception.activity_recognition.data_preprocessing.convert_to_ntu import mediapipe_to_ntu

# ----------------------------
# Paths
# ----------------------------
SKATEFORMER_DIR = r"D:\Year 4 UNI\Sava\SkateFormer"
sys.path.append(SKATEFORMER_DIR)

from model.SkateFormer import SkateFormer

CHECKPOINT = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\work_dir\sava_4class\best_4class.pt")

# ----------------------------
# Labels
# ----------------------------
CLASS_NAMES = ["EAT", "DRINK", "NAP", "SLEEP"]

# ----------------------------
# Pose -> SkateFormer settings
# ----------------------------
WINDOW_SIZE = 64
STRIDE = 1  # sliding window update every frame

# SkateFormer partition joint order (24 joints)
NEW_IDX_24 = np.array([
    6, 7, 21, 22,       # right_arm
    10, 11, 23, 24,     # left_arm
    12, 13, 14, 15,     # right_leg
    16, 17, 18, 19,     # left_leg
    4, 8, 5, 9,         # h_torso
    1, 2, 0, 3          # w_torso
], dtype=np.int64)

# ----------------------------
# Build model
# ----------------------------
def build_model(device):
    model = SkateFormer(
        in_channels=3,
        depths=(2, 2, 2, 2),
        channels=(96, 192, 192, 192),

        num_classes=4,
        embed_dim=96,
        num_people=2,
        num_frames=64,
        num_points=24,
        kernel_size=7,
        num_heads=32,

        type_1_size=(8, 8),
        type_2_size=(8, 12),
        type_3_size=(8, 8),
        type_4_size=(8, 12),

        attn_drop=0.5,
        head_drop=0.0,
        rel=True,
        drop_path=0.2,
        mlp_ratio=4.0,
        index_t=True
    ).to(device)

    ckpt = torch.load(str(CHECKPOINT), map_location=device)
    model.load_state_dict(ckpt["model"], strict=True)
    model.eval()
    return model


def mediapipe_frame_to_ntu24(results):
    """
    Returns a single frame skeleton in NTU24 format: (24,3)
    If no pose detected: returns None
    """
    if not results.pose_landmarks:
        return None

    # MediaPipe 33 joints
    kps33 = []
    for lm in results.pose_landmarks.landmark:
        kps33.append([lm.x, lm.y, lm.z])
    kps33 = np.array(kps33, dtype=np.float32)  # (33,3)

    # Convert (1,33,3) -> (1,25,3)
    ntu25 = mediapipe_to_ntu(kps33[np.newaxis, ...])[0]  # (25,3)

    # Partition to 24 joints
    ntu24 = ntu25[NEW_IDX_24, :]  # (24,3)
    return ntu24


def make_model_input_from_window(window_ntu24):
    """
    window_ntu24: (64,24,3)
    return tensor input for SkateFormer: (1,3,64,24,2) and index_t (1,64)
    """
    # add 2nd person zeros: (64,24,3,2)
    p2 = np.zeros_like(window_ntu24)
    stacked = np.stack([window_ntu24, p2], axis=-1)  # (64,24,3,2)

    # (64,24,3,2) -> (3,64,24,2)
    ctvm = stacked.transpose(2, 0, 1, 3)

    x = torch.from_numpy(ctvm).float().unsqueeze(0)  # (1,3,64,24,2)
    index_t = torch.arange(64, dtype=torch.long).unsqueeze(0)  # (1,64)
    return x, index_t


@torch.no_grad()
def predict(model, device, window_ntu24):
    x, index_t = make_model_input_from_window(window_ntu24)
    x = x.to(device)
    index_t = index_t.to(device)

    logits = model(x, index_t)  # (1,4)
    probs = torch.softmax(logits, dim=1)[0].detach().cpu().numpy()  # (4,)

    pred_id = int(np.argmax(probs))
    return pred_id, float(probs[pred_id]), probs


def main():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print("Device:", device)

    if not CHECKPOINT.exists():
        raise FileNotFoundError(f"Checkpoint not found: {CHECKPOINT}")

    model = build_model(device)
    print("✅ Loaded fine-tuned model:", CHECKPOINT)

    # MediaPipe Pose
    mp_pose = mp.solutions.pose
    mp_draw = mp.solutions.drawing_utils

    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        enable_segmentation=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    )

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        raise Exception("❌ Cannot open camera")

    window = []  # list of (24,3) frames

    print("✅ Live demo started. Press 'q' to quit.")

    last_pred = None
    last_conf = 0.0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = pose.process(rgb)

        # draw pose
        if results.pose_landmarks:
            mp_draw.draw_landmarks(frame, results.pose_landmarks, mp_pose.POSE_CONNECTIONS)

        ntu24 = mediapipe_frame_to_ntu24(results)

        # If pose detected, add to window; otherwise, keep previous window (or skip)
        if ntu24 is not None:
            window.append(ntu24)

            # sliding window
            if len(window) > WINDOW_SIZE:
                window = window[-WINDOW_SIZE:]

        # Predict when full window ready
        if len(window) == WINDOW_SIZE:
            window_np = np.stack(window, axis=0)  # (64,24,3)
            pred_id, conf, probs = predict(model, device, window_np)

            last_pred = CLASS_NAMES[pred_id]
            last_conf = conf

        # Overlay prediction
        if last_pred is not None:
            text = f"{last_pred}  ({last_conf*100:.1f}%)"
        else:
            text = "Collecting... (need 64 frames)"

        cv2.putText(frame, text, (10, 35),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)

        cv2.imshow("SAVA - Live Activity Demo (4 classes)", frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    pose.close()
    cv2.destroyAllWindows()
    print("🛑 Live demo stopped.")


if __name__ == "__main__":
    main()