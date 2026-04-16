"""
extract_keypoints_ntu.py
------------------------
Extracts SkateFormer-ready skeleton windows from NTU RGB+D .avi files.

Pipeline:
    .avi (RGB) → MediaPipe Pose (33 joints)
              → mediapipe_to_ntu() (25 joints)
              → normalize_skeleton() (scale+position invariant)
              → NEW_IDX_24 reorder (24 joints)
              → sliding 64-frame windows (stride=32)
              → .npy shape (3, 64, 24, 2)

Output: data/keypoints_v2/{CLASS}/ntu_{original_stem}.npy
"""

import os
import sys
import re
import cv2
import numpy as np
import mediapipe as mp
from pathlib import Path
from tqdm import tqdm

# ---------------------------------------------------------------------------
# Paths — run this script from the project root: python perception/activity_recognition/extract_keypoints_ntu.py
# ---------------------------------------------------------------------------
NTU_ROOT   = Path(r"D:\Year 4 UNI\Grad Project\Activity Recognition ROSElab\nturgbd_COMBINED")
SAVE_ROOT  = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints_v2")
SCRIPT_DIR = Path(__file__).parent

sys.path.insert(0, str(SCRIPT_DIR))
from data_preprocessing.convert_to_ntu import mediapipe_to_ntu, normalize_skeleton

# ---------------------------------------------------------------------------
# Action ID → Class label mapping (only IDs we care about)
# ---------------------------------------------------------------------------
ACTION_MAP = {
    "A001": "DRINK",   # drink water
    "A002": "EAT",     # eat meal
    "A042": "FALL",    # staggering (NTU60)
    "A043": "FALL",    # falling down (NTU60)
    "A046": "WALK",    # walking towards each other (NTU60, 2-person interaction)
    "A047": "WALK",    # walking apart from each other (NTU60, 2-person interaction)
    "A050": "WALK",    # walking towards each other (NTU60)
    "A051": "WALK",    # walking apart from each other (NTU60)
    "A062": "FALL",    # staggering (NTU120, different subjects/cameras)
    "A063": "FALL",    # falling down (NTU120, different subjects/cameras)
}

# ---------------------------------------------------------------------------
# SkateFormer joint reorder (NTU 25 → 24 joints)
# ---------------------------------------------------------------------------
NEW_IDX_24 = np.array([
    6, 7, 21, 22,
    10, 11, 23, 24,
    12, 13, 14, 15,
    16, 17, 18, 19,
    4, 8, 5, 9,
    1, 2, 0, 3
], dtype=np.int64)

# ---------------------------------------------------------------------------
# Extraction settings
# ---------------------------------------------------------------------------
WINDOW_SIZE    = 64
STRIDE         = 32    # overlapping windows → more samples per video
MAX_PER_ACTION = 500   # cap per action ID to keep classes balanced
MIN_POSE_RATIO = 0.25  # skip window if >75% frames had no pose (lowered for walk videos where person is far/small)

# ---------------------------------------------------------------------------
# MediaPipe setup
# ---------------------------------------------------------------------------
mp_pose    = mp.solutions.pose
POSE_MODEL = mp_pose.Pose(
    static_image_mode=False,
    model_complexity=1,
    enable_segmentation=False,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5,
)


def get_action_id(filename):
    """Extract action ID string (e.g. 'A001') from NTU filename."""
    m = re.search(r'(A\d{3})', filename)
    return m.group(1) if m else None


def extract_frames_mediapipe(video_path):
    """
    Run MediaPipe on every frame of a video.
    Returns list of (24,3) arrays (one per frame with detected pose).
    Frames with no pose are replaced with zeros.
    Returns (frames_ntu24, pose_detected_mask).
    """
    cap = cv2.VideoCapture(str(video_path))
    frames_ntu24 = []
    pose_mask    = []

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        rgb     = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = POSE_MODEL.process(rgb)

        if results.pose_landmarks:
            kps33 = np.array(
                [[lm.x, lm.y, lm.z] for lm in results.pose_landmarks.landmark],
                dtype=np.float32
            )  # (33, 3)
            ntu25 = mediapipe_to_ntu(kps33[np.newaxis, ...])[0]   # (25, 3)
            ntu25 = normalize_skeleton(ntu25)                       # normalize
            ntu24 = ntu25[NEW_IDX_24, :]                           # (24, 3)
            frames_ntu24.append(ntu24)
            pose_mask.append(True)
        else:
            frames_ntu24.append(np.zeros((24, 3), dtype=np.float32))
            pose_mask.append(False)

    cap.release()
    return frames_ntu24, pose_mask


def make_windows(frames, pose_mask):
    """
    Slide a 64-frame window with given stride over the frame list.
    Skip windows where too many frames had no pose.
    Returns list of (3, 64, 24, 2) arrays.
    """
    windows = []
    n = len(frames)

    for start in range(0, n - WINDOW_SIZE + 1, STRIDE):
        window_frames = frames[start: start + WINDOW_SIZE]
        window_mask   = pose_mask[start: start + WINDOW_SIZE]

        if sum(window_mask) < WINDOW_SIZE * MIN_POSE_RATIO:
            continue  # too many missing poses in this window

        window_np = np.stack(window_frames, axis=0)  # (64, 24, 3)

        # Add second person (zeros)
        p2      = np.zeros_like(window_np)
        stacked = np.stack([window_np, p2], axis=-1)  # (64, 24, 3, 2)

        # (64, 24, 3, 2) → (3, 64, 24, 2)
        ctvm = stacked.transpose(2, 0, 1, 3).astype(np.float32)
        windows.append(ctvm)

    return windows


def main():
    SAVE_ROOT.mkdir(parents=True, exist_ok=True)
    for cls in ACTION_MAP.values():
        (SAVE_ROOT / cls).mkdir(exist_ok=True)

    # Collect all .avi files per target action ID
    action_files = {aid: [] for aid in ACTION_MAP}
    for folder in sorted(NTU_ROOT.iterdir()):
        if not folder.is_dir():
            continue
        for f in folder.glob("*.avi"):
            aid = get_action_id(f.name)
            if aid in action_files:
                action_files[aid].append(f)

    print("Files found per action:")
    for aid, files in action_files.items():
        print(f"  {aid} ({ACTION_MAP[aid]}): {len(files)} videos")

    # Process each action ID
    for aid, files in action_files.items():
        cls        = ACTION_MAP[aid]
        save_dir   = SAVE_ROOT / cls
        capped     = files[:MAX_PER_ACTION]
        windows_saved = 0

        print(f"\nExtracting {aid} → {cls} ({len(capped)} videos)...")

        for video_path in tqdm(capped, desc=f"{aid}"):
            # Skip if already extracted (allows safe re-runs)
            first_window_name = save_dir / f"ntu_{video_path.stem}_w00.npy"
            if first_window_name.exists():
                continue

            frames, mask = extract_frames_mediapipe(video_path)

            if len(frames) < WINDOW_SIZE:
                continue  # video too short

            windows = make_windows(frames, mask)

            for i, w in enumerate(windows):
                save_name = f"ntu_{video_path.stem}_w{i:02d}.npy"
                np.save(save_dir / save_name, w)
                windows_saved += 1

        print(f"  → Saved {windows_saved} windows for {cls} from {aid}")

    POSE_MODEL.close()

    print("\n✅ NTU extraction complete.")
    print("Summary:")
    for cls in set(ACTION_MAP.values()):
        count = len(list((SAVE_ROOT / cls).glob("ntu_*.npy")))
        print(f"  {cls}: {count} windows")


if __name__ == "__main__":
    main()
