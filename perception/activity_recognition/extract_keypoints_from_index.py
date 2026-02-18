import csv
import os
from pathlib import Path

import cv2
import numpy as np
import mediapipe as mp

from perception.activity_recognition.data_preprocessing.convert_to_ntu import mediapipe_to_ntu

# -----------------------
# Paths
# -----------------------
INDEX_CSV = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\video_index.csv")
OUT_DIR = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints")

# -----------------------
# Settings
# -----------------------
WINDOW_SIZE = 64
STRIDE = 32              # overlap windows (64 with stride 32 = 50% overlap)
MAX_WINDOWS_PER_VIDEO = 999999  # you can reduce later for speed
MIN_DETECTED_FRAMES = 40        # skip windows where pose fails too much

# SkateFormer partition joint order (24 joints)
NEW_IDX_24 = np.array([
    6, 7, 21, 22,       # right_arm
    10, 11, 23, 24,     # left_arm
    12, 13, 14, 15,     # right_leg
    16, 17, 18, 19,     # left_leg
    4, 8, 5, 9,         # h_torso
    1, 2, 0, 3          # w_torso
], dtype=np.int64)

VIDEO_EXTS = {".mp4", ".avi", ".mov", ".mkv"}


def read_index(csv_path: Path):
    rows = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append((r["label"].strip(), r["video_path"].strip()))
    return rows


def extract_mediapipe_sequence(video_path: str, pose):
    """
    Returns:
      seq: np.ndarray shape (T, 33, 3) or None if cannot read
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return None

    frames_keypoints = []

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = pose.process(rgb)

        if results.pose_landmarks:
            kps = []
            for lm in results.pose_landmarks.landmark:
                kps.append([lm.x, lm.y, lm.z])
            frames_keypoints.append(np.array(kps, dtype=np.float32))  # (33,3)
        else:
            frames_keypoints.append(None)

    cap.release()

    if len(frames_keypoints) == 0:
        return None

    return frames_keypoints  # list length T containing (33,3) or None


def fill_missing(frames_keypoints):
    """
    Replace None frames with the previous valid frame; if start is None, use first future valid.
    """
    T = len(frames_keypoints)

    # find first valid
    first_valid = None
    for i in range(T):
        if frames_keypoints[i] is not None:
            first_valid = frames_keypoints[i]
            break
    if first_valid is None:
        return None  # all missing

    # forward fill
    last = first_valid
    filled = []
    for i in range(T):
        if frames_keypoints[i] is None:
            filled.append(last)
        else:
            last = frames_keypoints[i]
            filled.append(last)

    return np.stack(filled, axis=0)  # (T,33,3)


def to_skateformer_input(seq_33):
    """
    seq_33: (T,33,3)
    return: (T,24,3,2) for a single video timeline (not windowed yet)
    """
    # MediaPipe33 -> NTU25
    ntu25 = mediapipe_to_ntu(seq_33)  # (T,25,3)

    # NTU25 -> NTU24 partition order
    ntu24 = ntu25[:, NEW_IDX_24, :]   # (T,24,3)

    # add 2nd person (zeros)
    person2 = np.zeros_like(ntu24)    # (T,24,3)
    stacked = np.stack([ntu24, person2], axis=-1)  # (T,24,3,2)

    return stacked


def window_and_save(stacked_TV32, label, video_path):
    """
    stacked_TV32: (T,24,3,2)
    Save windows as (3,64,24,2) .npy files in OUT_DIR/label/
    """
    T = stacked_TV32.shape[0]
    out_label_dir = OUT_DIR / label
    out_label_dir.mkdir(parents=True, exist_ok=True)

    base = Path(video_path).stem
    saved = 0

    for start in range(0, max(1, T - WINDOW_SIZE + 1), STRIDE):
        end = start + WINDOW_SIZE
        if end > T:
            break

        window = stacked_TV32[start:end]  # (64,24,3,2)

        # quality check: count how many frames are non-zero (rough proxy)
        # (since we filled missing, this mostly checks for totally empty video)
        nonzero_frames = np.sum(np.abs(window)) > 0
        # We'll instead check if original had enough valid frames using MIN_DETECTED_FRAMES logic outside,
        # but keep here simple.

        # transpose to SkateFormer: (C,T,V,M)
        window_ctvm = window.transpose(2, 0, 1, 3)  # (3,64,24,2)

        out_path = out_label_dir / f"{base}_s{start:05d}.npy"
        np.save(out_path, window_ctvm)
        saved += 1

        if saved >= MAX_WINDOWS_PER_VIDEO:
            break

    return saved


def main():
    if not INDEX_CSV.exists():
        raise FileNotFoundError(f"Missing index: {INDEX_CSV}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rows = read_index(INDEX_CSV)
    print(f"✅ Loaded index rows: {len(rows)}")

    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(static_image_mode=False, model_complexity=1,
                        enable_segmentation=False, min_detection_confidence=0.5,
                        min_tracking_confidence=0.5)

    total_windows = 0
    skipped = 0

    for i, (label, video_path) in enumerate(rows, start=1):
        if not Path(video_path).exists():
            print(f"⚠️ Missing file, skipping: {video_path}")
            skipped += 1
            continue

        print(f"[{i}/{len(rows)}] {label} | {video_path}")

        frames_kp = extract_mediapipe_sequence(video_path, pose)
        if frames_kp is None:
            print("  ❌ Could not read / no frames.")
            skipped += 1
            continue

        # Count detected frames (before fill)
        detected = sum(1 for x in frames_kp if x is not None)
        if detected < MIN_DETECTED_FRAMES:
            print(f"  ⚠️ Too few pose frames ({detected}), skipping.")
            skipped += 1
            continue

        seq_33 = fill_missing(frames_kp)
        if seq_33 is None:
            print("  ⚠️ All frames missing, skipping.")
            skipped += 1
            continue

        stacked = to_skateformer_input(seq_33)  # (T,24,3,2)

        saved = window_and_save(stacked, label, video_path)
        total_windows += saved
        print(f"  ✅ Saved windows: {saved} (detected frames: {detected})")

    pose.close()
    print("\n==============================")
    print("✅ Done")
    print("Total windows saved:", total_windows)
    print("Videos skipped:", skipped)
    print("Output folder:", OUT_DIR)
    print("==============================\n")


if __name__ == "__main__":
    main()