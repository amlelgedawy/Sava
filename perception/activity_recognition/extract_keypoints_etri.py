"""
extract_keypoints_etri.py
-------------------------
Extracts SkateFormer-ready skeleton windows from ETRI-Activity3D CSV files.

ETRI uses Kinect v2 — same 25-joint ordering as NTU RGB+D.
No MediaPipe needed: read 3D coords directly from CSV.

Pipeline:
    .csv (25 joints, Kinect v2)
        → read joint{N}_3dX/Y/Z  → (T, 25, 3)
        → normalize_skeleton() per frame
        → NEW_IDX_24 reorder     → (T, 24, 3)
        → sliding 64-frame windows (stride=32)
        → .npy shape (3, 64, 24, 2)

Output: data/keypoints_v2/{CLASS}/etri_{stem}.npy

Action ID mapping (identified via identify_etri_classes.py):
    A045, A048 → WALK
    A040       → EAT
    A016, A017 → DRINK
    A053, A037, A049 → SLEEP

Run from project root:
    python perception/activity_recognition/extract_keypoints_etri.py
"""

import re
import sys
import numpy as np
import pandas as pd
from pathlib import Path
from tqdm import tqdm

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ETRI_ROOT  = Path(r"D:\Year 4 UNI\Elderly Dataset")
SAVE_ROOT  = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints_v2")
SCRIPT_DIR = Path(__file__).parent

sys.path.insert(0, str(SCRIPT_DIR))
from data_preprocessing.convert_to_ntu import normalize_skeleton

# ---------------------------------------------------------------------------
# Action ID → SAVA class mapping
# (identified via identify_etri_classes.py skeleton statistics)
# ---------------------------------------------------------------------------
ACTION_MAP = {
    "A045": "WALK",   # walking — highest foot_range (2.55), 806 frames
    "A048": "WALK",   # walking variant — foot_range (2.49), 800 frames
    "A040": "EAT",    # eating — lowest wrist_to_head (0.244), stationary
    "A016": "DRINK",  # drinking — wrist_to_head (0.295), upright, stationary
    "A017": "DRINK",  # drinking variant — wrist_to_head (0.290)
    "A053": "SLEEP",  # lying flat — avg_hip_y (-0.954), completely still
    "A037": "SLEEP",  # lying on sofa — avg_hip_y (-0.455), still
    "A049": "SLEEP",  # lying down — avg_hip_y (-0.468), still
}

# ---------------------------------------------------------------------------
# SkateFormer joint reorder (NTU 25 → 24 joints, partition=True)
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
WINDOW_SIZE        = 64
STRIDE             = 32
MAX_PER_ACTION     = 600   # cap per action ID for class balance
MIN_FRAMES         = 64    # skip files shorter than one window


def get_action_id(filename):
    m = re.match(r'(A\d+)', filename)
    return m.group(1) if m else None


def read_etri_csv(csv_path):
    """
    Read ETRI CSV → skeleton (T, 25, 3) float32.
    Returns None if file is unreadable or too short.
    """
    try:
        df = pd.read_csv(csv_path)
    except Exception:
        return None

    if len(df) < MIN_FRAMES:
        return None

    T        = len(df)
    skeleton = np.zeros((T, 25, 3), dtype=np.float32)

    for j in range(25):
        col_x = f"joint{j+1}_3dX"
        col_y = f"joint{j+1}_3dY"
        col_z = f"joint{j+1}_3dZ"
        if col_x not in df.columns:
            return None
        skeleton[:, j, 0] = df[col_x].values.astype(np.float32)
        skeleton[:, j, 1] = df[col_y].values.astype(np.float32)
        skeleton[:, j, 2] = df[col_z].values.astype(np.float32)

    return skeleton


def make_windows(skeleton_t25):
    """
    skeleton_t25: (T, 25, 3)
    Normalizes per frame, reorders to 24 joints, slides 64-frame windows.
    Returns list of (3, 64, 24, 2) arrays.
    """
    T = len(skeleton_t25)
    windows = []

    for start in range(0, T - WINDOW_SIZE + 1, STRIDE):
        window_25 = skeleton_t25[start: start + WINDOW_SIZE]  # (64, 25, 3)

        # Normalize each frame independently
        window_norm = np.stack(
            [normalize_skeleton(window_25[t]) for t in range(WINDOW_SIZE)],
            axis=0
        )  # (64, 25, 3)

        # Reorder to 24 joints
        window_24 = window_norm[:, NEW_IDX_24, :]  # (64, 24, 3)

        # Add second person (zeros)
        p2      = np.zeros_like(window_24)
        stacked = np.stack([window_24, p2], axis=-1)  # (64, 24, 3, 2)

        # → (3, 64, 24, 2)
        ctvm = stacked.transpose(2, 0, 1, 3).astype(np.float32)
        windows.append(ctvm)

    return windows


def main():
    SAVE_ROOT.mkdir(parents=True, exist_ok=True)
    for cls in set(ACTION_MAP.values()):
        (SAVE_ROOT / cls).mkdir(exist_ok=True)

    # Collect CSV files per target action ID
    action_files = {aid: [] for aid in ACTION_MAP}

    for participant_folder in sorted(ETRI_ROOT.iterdir()):
        if not participant_folder.is_dir():
            continue
        for csv_file in participant_folder.glob("*.csv"):
            aid = get_action_id(csv_file.name)
            if aid in action_files:
                action_files[aid].append(csv_file)

    print("Files found per action:")
    for aid, files in action_files.items():
        print(f"  {aid} ({ACTION_MAP[aid]}): {len(files)} CSVs")

    # Process each action
    total_saved = {cls: 0 for cls in set(ACTION_MAP.values())}

    for aid, files in action_files.items():
        cls      = ACTION_MAP[aid]
        save_dir = SAVE_ROOT / cls
        capped   = files[:MAX_PER_ACTION]

        print(f"\nExtracting {aid} → {cls} ({len(capped)} files)...")

        windows_saved = 0
        for csv_path in tqdm(capped, desc=aid):
            skeleton = read_etri_csv(csv_path)
            if skeleton is None:
                continue

            windows = make_windows(skeleton)
            for i, w in enumerate(windows):
                save_name = f"etri_{csv_path.stem}_w{i:02d}.npy"
                np.save(save_dir / save_name, w)
                windows_saved += 1

        total_saved[cls] += windows_saved
        print(f"  → {windows_saved} windows saved for {cls} from {aid}")

    print("\n✅ ETRI extraction complete.")
    print("Summary (windows per class from ETRI):")
    for cls, count in total_saved.items():
        print(f"  {cls}: {count} windows")

    print("\nTotal keypoints_v2 counts (all sources combined):")
    for cls in ["WALK", "EAT", "DRINK", "SLEEP", "FALL"]:
        d     = SAVE_ROOT / cls
        count = len(list(d.glob("*.npy"))) if d.exists() else 0
        print(f"  {cls}: {count} windows")


if __name__ == "__main__":
    main()
