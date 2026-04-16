"""
extract_keypoints_upfall.py
---------------------------
Extracts SkateFormer-ready skeleton windows from the 3D Skeleton UP-Fall dataset.

Dataset format:
  - 5 subjects, 5 fall activity types (A1-A5), multiple trials
  - CSV: 33 joints (Joint1_X/Y/Z ... Joint33_X/Y/Z) + LABEL column
  - Coordinates are MediaPipe-normalized (0-1 range) — same as live inference
  - 100 frames per file → 1-2 windows of 64 frames each

Pipeline:
    .csv (33 joints, MediaPipe BlazePose normalized)
        → read Joint{N}_X/Y/Z  → (T, 33, 3)
        → mediapipe_to_ntu()   → (T, 25, 3)
        → normalize_skeleton() → scale+position invariant
        → NEW_IDX_24 reorder   → (T, 24, 3)
        → sliding 64-frame windows (stride=32)
        → .npy shape (3, 64, 24, 2)

All 5 activity types are falls:
    A1 = forward fall (hands)
    A2 = forward fall (knees)
    A3 = backward fall
    A4 = sideways fall
    A5 = sitting in empty chair (sudden fall)

Output: data/keypoints_v2/FALL/upfall_*.npy

Run from project root:
    python perception/activity_recognition/extract_keypoints_upfall.py
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
UPFALL_ROOT = Path(r"D:\Year 4 UNI\Fall Detection dataset")
SAVE_ROOT   = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints_v2")
SCRIPT_DIR  = Path(__file__).parent

sys.path.insert(0, str(SCRIPT_DIR))
from data_preprocessing.convert_to_ntu import mediapipe_to_ntu, normalize_skeleton

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
# Settings
# ---------------------------------------------------------------------------
WINDOW_SIZE = 64
STRIDE      = 32   # 100 frames → windows at [0:64] and [32:96]


def read_upfall_csv(csv_path):
    """
    Read UP-Fall CSV → (T, 33, 3) float32.
    Columns: Joint1_X, Joint1_Y, Joint1_Z, ..., Joint33_X, Joint33_Y, Joint33_Z, LABEL
    Returns None if file is unreadable or too short.
    """
    try:
        df = pd.read_csv(csv_path)
    except Exception:
        return None

    if len(df) < WINDOW_SIZE:
        return None

    T        = len(df)
    skeleton = np.zeros((T, 33, 3), dtype=np.float32)

    for j in range(33):
        col_x = f"Joint{j+1}_X"
        col_y = f"Joint{j+1}_Y"
        col_z = f"Joint{j+1}_Z"
        if col_x not in df.columns:
            return None
        skeleton[:, j, 0] = df[col_x].values.astype(np.float32)
        skeleton[:, j, 1] = df[col_y].values.astype(np.float32)
        skeleton[:, j, 2] = df[col_z].values.astype(np.float32)

    return skeleton


def process_skeleton(skeleton_t33):
    """
    skeleton_t33: (T, 33, 3) MediaPipe format
    Returns list of (3, 64, 24, 2) window arrays.
    """
    T = len(skeleton_t33)
    windows = []

    for start in range(0, T - WINDOW_SIZE + 1, STRIDE):
        window_33 = skeleton_t33[start: start + WINDOW_SIZE]  # (64, 33, 3)

        # MediaPipe 33 → NTU 25
        window_25 = mediapipe_to_ntu(window_33)  # (64, 25, 3)

        # Normalize each frame
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
    save_dir = SAVE_ROOT / "FALL"
    save_dir.mkdir(parents=True, exist_ok=True)

    # Collect all CSV files
    all_csvs = sorted(UPFALL_ROOT.glob("subject*/*.csv"))
    print(f"Found {len(all_csvs)} UP-Fall CSV files across all subjects.")

    # Check activity distribution
    act_counts = {}
    for f in all_csvs:
        m = re.search(r'A(\d+)', f.name)
        if m:
            act = f"A{m.group(1)}"
            act_counts[act] = act_counts.get(act, 0) + 1
    print("Files per activity:", act_counts)
    print("All activities → FALL class\n")

    windows_saved = 0
    skipped       = 0

    for csv_path in tqdm(all_csvs, desc="UP-Fall"):
        # Skip if already extracted
        save_name_w0 = save_dir / f"upfall_{csv_path.parent.name}_{csv_path.stem}_w00.npy"
        if save_name_w0.exists():
            continue

        skeleton = read_upfall_csv(csv_path)
        if skeleton is None:
            skipped += 1
            continue

        windows = process_skeleton(skeleton)
        for i, w in enumerate(windows):
            save_name = f"upfall_{csv_path.parent.name}_{csv_path.stem}_w{i:02d}.npy"
            np.save(save_dir / save_name, w)
            windows_saved += 1

    print(f"\n✅ UP-Fall extraction complete.")
    print(f"   Windows saved: {windows_saved}")
    print(f"   Skipped: {skipped}")

    # Final FALL class count
    total_fall = len(list(save_dir.glob("*.npy")))
    print(f"\nTotal FALL windows (all sources): {total_fall}")


if __name__ == "__main__":
    main()
