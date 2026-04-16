"""
extract_keypoints_adl.py
------------------------
Extracts SkateFormer-ready skeleton windows from ADL dataset .mp4 files.

ADL videos are short (12-20 frames). We loop each video until we reach
64 frames to fill one window, then save a single window per video.

Pipeline:
    .mp4 (RGB) → MediaPipe Pose (33 joints)
              → mediapipe_to_ntu() (25 joints)
              → normalize_skeleton() (scale+position invariant)
              → NEW_IDX_24 reorder (24 joints)
              → loop-fill to 64 frames
              → .npy shape (3, 64, 24, 2)

Output: data/keypoints_v2/{CLASS}/adl_{participant}_{action}_{session}.npy
"""

import os
import sys
import cv2
import numpy as np
import mediapipe as mp
from pathlib import Path
from tqdm import tqdm

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ADL_ROOT  = Path(r"D:\Year 4 UNI\ADL dataset\data")
SAVE_ROOT = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints_v2")
SCRIPT_DIR = Path(__file__).parent

sys.path.insert(0, str(SCRIPT_DIR))
from data_preprocessing.convert_to_ntu import mediapipe_to_ntu, normalize_skeleton

# ---------------------------------------------------------------------------
# ADL class → SAVA class mapping (only classes we use)
# ---------------------------------------------------------------------------
CLASS_MAP = {
    "Eat.Snack":        "EAT",
    "Eat.Useutensil":   "EAT",
    "Drink.Fromcup":    "DRINK",
    "Drink.Frombottle": "DRINK",
    "Nap":              "SLEEP",
    "Lay.Onbed":        "SLEEP",
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

WINDOW_SIZE    = 64
STRIDE         = 16   # sliding window stride over loop-filled sequence
LOOP_FRAMES    = 128  # loop-fill target; gives 4 windows per video at stride=16
MIN_POSE_RATIO = 0.5  # skip window if >50% frames have no pose

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


def extract_frames_mediapipe(video_path):
    """
    Extract all frames from a video through MediaPipe.
    Returns (frames_ntu24, pose_mask).
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
            )
            ntu25 = mediapipe_to_ntu(kps33[np.newaxis, ...])[0]
            ntu25 = normalize_skeleton(ntu25)
            ntu24 = ntu25[NEW_IDX_24, :]
            frames_ntu24.append(ntu24)
            pose_mask.append(True)
        else:
            frames_ntu24.append(np.zeros((24, 3), dtype=np.float32))
            pose_mask.append(False)

    cap.release()
    return frames_ntu24, pose_mask


def loop_to_length(frames, pose_mask, target):
    """
    Loop frames/mask until we reach at least `target` frames, then truncate.
    """
    if len(frames) == 0:
        return None, None

    looped_frames = []
    looped_mask   = []

    while len(looped_frames) < target:
        looped_frames.extend(frames)
        looped_mask.extend(pose_mask)

    return looped_frames[:target], looped_mask[:target]


def make_windows_from_sequence(frames, pose_mask):
    """
    Slide a WINDOW_SIZE window with STRIDE over the sequence.
    Returns list of (3, 64, 24, 2) arrays, skipping windows with too many missing poses.
    """
    windows = []
    n = len(frames)

    for start in range(0, n - WINDOW_SIZE + 1, STRIDE):
        w_frames = frames[start: start + WINDOW_SIZE]
        w_mask   = pose_mask[start: start + WINDOW_SIZE]

        if sum(w_mask) < WINDOW_SIZE * MIN_POSE_RATIO:
            continue

        window_np = np.stack(w_frames, axis=0)          # (64, 24, 3)
        p2        = np.zeros_like(window_np)
        stacked   = np.stack([window_np, p2], axis=-1)  # (64, 24, 3, 2)
        windows.append(stacked.transpose(2, 0, 1, 3).astype(np.float32))  # (3, 64, 24, 2)

    return windows


def main():
    SAVE_ROOT.mkdir(parents=True, exist_ok=True)
    for cls in set(CLASS_MAP.values()):
        (SAVE_ROOT / cls).mkdir(exist_ok=True)

    saved_counts = {cls: 0 for cls in set(CLASS_MAP.values())}
    skipped      = 0

    # Walk: participant → action_class → session → .mp4
    participants = sorted([p for p in ADL_ROOT.iterdir() if p.is_dir()])

    for participant in participants:
        for action_dir in sorted(participant.iterdir()):
            if not action_dir.is_dir():
                continue

            adl_class = action_dir.name
            if adl_class not in CLASS_MAP:
                continue  # not a class we care about

            sava_class = CLASS_MAP[adl_class]
            save_dir   = SAVE_ROOT / sava_class

            videos = sorted(action_dir.glob("**/*.mp4"))

            for video_path in tqdm(videos, desc=f"{participant.name}/{adl_class}", leave=False):
                frames, mask = extract_frames_mediapipe(video_path)

                if len(frames) == 0:
                    skipped += 1
                    continue

                looped_frames, looped_mask = loop_to_length(frames, mask, LOOP_FRAMES)
                if looped_frames is None:
                    skipped += 1
                    continue

                windows = make_windows_from_sequence(looped_frames, looped_mask)

                if len(windows) == 0:
                    skipped += 1
                    continue

                # Build a clean save name from path components
                session = video_path.stem  # e.g. 00101_c4s0
                for i, w in enumerate(windows):
                    save_name = f"adl_{participant.name}_{adl_class}_{session}_w{i:02d}.npy"
                    np.save(save_dir / save_name, w)
                    saved_counts[sava_class] += 1

    POSE_MODEL.close()

    print("\n✅ ADL extraction complete.")
    print(f"Skipped (no pose / empty): {skipped}")
    print("Summary:")
    for cls, count in saved_counts.items():
        print(f"  {cls}: {count} windows")


if __name__ == "__main__":
    main()
