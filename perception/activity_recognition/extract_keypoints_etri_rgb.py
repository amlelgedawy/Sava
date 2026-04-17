"""
extract_keypoints_etri_rgb.py
------------------------------
Extracts SkateFormer-ready skeleton windows from ETRI-Activity3D RGB videos.

Dataset structure:
    D:/Year 4 UNI/ETRI RGB dataset/
        P001-P010/P001/ ... P010/
        P011-P020/P011/ ... P020/
    Each participant folder contains .mp4 files named:
        A001_P001_G001_C001.mp4  (Action_Participant_Group_Camera)

Videos: 161 frames @ 20fps (~8s) — well above 64-frame minimum, no looping needed.
Participants P001-P020 are all elderly subjects.

Pipeline:
    .mp4 (RGB) → MediaPipe Pose (33 joints)
              → mediapipe_to_ntu() (25 joints)
              → normalize_skeleton() (scale+position invariant)
              → NEW_IDX_24 reorder (24 joints)
              → sliding 64-frame windows (stride=32)
              → .npy shape (3, 64, 24, 2)

Output: data/keypoints/{CLASS}/etri_{stem}_w{i:02d}.npy
"""

import sys
import cv2
import numpy as np
import mediapipe as mp
from pathlib import Path
from tqdm import tqdm

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ETRI_ROOT = Path(r"D:\Year 4 UNI\ETRI RGB dataset")
SAVE_ROOT = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints")
SCRIPT_DIR = Path(__file__).parent

sys.path.insert(0, str(SCRIPT_DIR))
from data_preprocessing.convert_to_ntu import mediapipe_to_ntu, normalize_skeleton

# ---------------------------------------------------------------------------
# Action ID → SAVA class mapping
# ---------------------------------------------------------------------------
ACTION_MAP = {
    "A001": "EAT",        # eating with fork
    "A002": "DRINK",      # drinking from cup/bottle
    "A003": "DRINK",      # pouring water
    "A033": "USE_PHONE",  # talking on phone
    "A034": "USE_PHONE",  # playing on phone/texting
    "A041": "WALK",       # walking in
    "A042": "SIT",        # sitting down
    "A043": "STAND",      # standing up
    "A044": "SLEEP",      # lying down
    "A050": "FALL",       # falling
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
STRIDE         = 32    # consistent with NTU extraction
MAX_PER_ACTION = 500   # cap per action ID to keep classes balanced
MIN_POSE_RATIO = 0.25  # skip window if >75% frames had no pose

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
    """Extract action ID from ETRI filename: A001_P001_G001_C001.mp4 → 'A001'"""
    return Path(filename).stem.split("_")[0]


def extract_frames_mediapipe(video_path):
    """
    Run MediaPipe on every frame of a video.
    Returns (frames_ntu24, pose_mask).
    Frames with no detected pose are replaced with zeros.
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
            ntu25 = mediapipe_to_ntu(kps33[np.newaxis, ...])[0]  # (25, 3)
            ntu25 = normalize_skeleton(ntu25)
            ntu24 = ntu25[NEW_IDX_24, :]                          # (24, 3)
            frames_ntu24.append(ntu24)
            pose_mask.append(True)
        else:
            frames_ntu24.append(np.zeros((24, 3), dtype=np.float32))
            pose_mask.append(False)

    cap.release()
    return frames_ntu24, pose_mask


def make_windows(frames, pose_mask):
    """
    Slide a 64-frame window with STRIDE over the frame list.
    Skip windows where too many frames had no pose.
    Returns list of (3, 64, 24, 2) arrays.
    """
    windows = []
    n = len(frames)

    for start in range(0, n - WINDOW_SIZE + 1, STRIDE):
        window_frames = frames[start: start + WINDOW_SIZE]
        window_mask   = pose_mask[start: start + WINDOW_SIZE]

        if sum(window_mask) < WINDOW_SIZE * MIN_POSE_RATIO:
            continue

        window_np = np.stack(window_frames, axis=0)          # (64, 24, 3)
        p2        = np.zeros_like(window_np)
        stacked   = np.stack([window_np, p2], axis=-1)       # (64, 24, 3, 2)
        ctvm      = stacked.transpose(2, 0, 1, 3).astype(np.float32)  # (3, 64, 24, 2)
        windows.append(ctvm)

    return windows


def main():
    SAVE_ROOT.mkdir(parents=True, exist_ok=True)
    for cls in set(ACTION_MAP.values()):
        (SAVE_ROOT / cls).mkdir(exist_ok=True)

    # Collect all .mp4 files grouped by action ID
    action_files = {aid: [] for aid in ACTION_MAP}

    for batch_dir in sorted(ETRI_ROOT.iterdir()):
        if not batch_dir.is_dir():
            continue
        for participant_dir in sorted(batch_dir.iterdir()):
            if not participant_dir.is_dir():
                continue
            for f in sorted(participant_dir.glob("*.mp4")):
                aid = get_action_id(f.name)
                if aid in action_files:
                    action_files[aid].append(f)

    print("Files found per action:")
    for aid, files in action_files.items():
        print(f"  {aid} ({ACTION_MAP[aid]}): {len(files)} videos")

    saved_counts = {cls: 0 for cls in set(ACTION_MAP.values())}

    for aid, files in action_files.items():
        cls      = ACTION_MAP[aid]
        save_dir = SAVE_ROOT / cls
        capped   = files[:MAX_PER_ACTION]

        print(f"\nExtracting {aid} → {cls} ({len(capped)} videos)...")

        for video_path in tqdm(capped, desc=f"{aid}"):
            # Skip if already extracted (allows safe re-runs)
            first_window = save_dir / f"etri_{video_path.stem}_w00.npy"
            if first_window.exists():
                continue

            frames, mask = extract_frames_mediapipe(video_path)

            if len(frames) < WINDOW_SIZE:
                continue  # video too short — skip, never loop

            windows = make_windows(frames, mask)

            for i, w in enumerate(windows):
                save_name = f"etri_{video_path.stem}_w{i:02d}.npy"
                np.save(save_dir / save_name, w)
                saved_counts[cls] += 1

    POSE_MODEL.close()

    print("\n✅ ETRI extraction complete.")
    print("Summary:")
    for cls, count in saved_counts.items():
        print(f"  {cls}: {count} windows")


if __name__ == "__main__":
    main()
