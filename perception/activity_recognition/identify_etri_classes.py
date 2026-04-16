"""
identify_etri_classes.py
------------------------
Reads one sample CSV per ETRI action class (A001–A055) and computes
skeleton statistics to help identify which action IDs correspond to
WALK, EAT, DRINK, and SLEEP.

Statistics computed per action:
  - avg_hip_y        : average Y of hip joint (low = lying down = SLEEP)
  - wrist_to_nose    : average distance from wrists to nose (high = eating/drinking)
  - foot_range       : range of foot X position across frames (high = walking)
  - spine_std        : std of spine Y (high = dynamic movement)

Run from project root:
    python perception/activity_recognition/identify_etri_classes.py

Output: prints a table sorted by each statistic to help identify target classes.
"""

import re
import numpy as np
import pandas as pd
from pathlib import Path

# ---------------------------------------------------------------------------
# ETRI dataset path
# ---------------------------------------------------------------------------
ETRI_ROOT = Path(r"D:\Year 4 UNI\Elderly Dataset")

# ---------------------------------------------------------------------------
# ETRI Kinect v2 joint indices (0-indexed, same as NTU)
# Joint 0  = SpineBase  (hip center)
# Joint 3  = SpineShoulder
# Joint 4  = Neck / Head
# Joint 6  = ShoulderLeft
# Joint 10 = ShoulderRight
# Joint 7  = ElbowLeft
# Joint 11 = ElbowRight
# Joint 8  = WristLeft
# Joint 12 = WristRight
# Joint 15 = FootLeft
# Joint 19 = FootRight
# ---------------------------------------------------------------------------
JOINT_HIP        = 0    # SpineBase
JOINT_SPINE_MID  = 1    # SpineMid
JOINT_NECK       = 2    # Neck
JOINT_HEAD       = 3    # Head
JOINT_WRIST_L    = 6    # WristLeft
JOINT_WRIST_R    = 10   # WristRight
JOINT_FOOT_L     = 15   # FootLeft
JOINT_FOOT_R     = 19   # FootRight


def read_etri_csv(csv_path):
    """
    Read an ETRI CSV and return skeleton array of shape (T, 25, 3).
    Extracts only the 3dX, 3dY, 3dZ columns for each of the 25 joints.
    Returns None if file is empty or malformed.
    """
    try:
        df = pd.read_csv(csv_path)
    except Exception:
        return None

    if df.empty or len(df) < 5:
        return None

    # Build (T, 25, 3) array from joint{1..25}_3dX/Y/Z columns
    # Note: ETRI uses 1-indexed joint names (joint1 to joint25)
    T = len(df)
    skeleton = np.zeros((T, 25, 3), dtype=np.float32)

    for j in range(25):
        col_x = f"joint{j+1}_3dX"
        col_y = f"joint{j+1}_3dY"
        col_z = f"joint{j+1}_3dZ"
        if col_x not in df.columns:
            return None
        skeleton[:, j, 0] = df[col_x].values
        skeleton[:, j, 1] = df[col_y].values
        skeleton[:, j, 2] = df[col_z].values

    return skeleton


def compute_stats(skeleton):
    """
    skeleton: (T, 25, 3)
    Returns dict of statistics useful for identifying action type.
    """
    # Average hip Y — low (negative, close to ground) = lying down
    avg_hip_y = float(skeleton[:, JOINT_HIP, 1].mean())

    # Average wrist-to-head distance — high = arms raised (eating/drinking)
    head_pos   = skeleton[:, JOINT_HEAD, :]       # (T, 3)
    wrist_l    = skeleton[:, JOINT_WRIST_L, :]
    wrist_r    = skeleton[:, JOINT_WRIST_R, :]
    dist_l     = np.linalg.norm(wrist_l - head_pos, axis=1).mean()
    dist_r     = np.linalg.norm(wrist_r - head_pos, axis=1).mean()
    wrist_to_head = float(min(dist_l, dist_r))    # take the closer wrist

    # Foot horizontal range — high = walking (feet moving laterally)
    foot_l_x   = skeleton[:, JOINT_FOOT_L, 0]
    foot_r_x   = skeleton[:, JOINT_FOOT_R, 0]
    foot_range  = float(
        (foot_l_x.max() - foot_l_x.min()) + (foot_r_x.max() - foot_r_x.min())
    )

    # Spine Y std — high = dynamic movement
    spine_std = float(skeleton[:, JOINT_SPINE_MID, 1].std())

    return {
        "avg_hip_y":    avg_hip_y,
        "wrist_to_head": wrist_to_head,
        "foot_range":   foot_range,
        "spine_std":    spine_std,
        "n_frames":     len(skeleton),
    }


def get_action_id(filename):
    m = re.match(r'(A\d+)', filename)
    return m.group(1) if m else None


def main():
    # Collect one sample file per action ID
    sample_per_action = {}

    for participant_folder in sorted(ETRI_ROOT.iterdir()):
        if not participant_folder.is_dir():
            continue
        for csv_file in sorted(participant_folder.glob("*.csv")):
            aid = get_action_id(csv_file.name)
            if aid and aid not in sample_per_action:
                sample_per_action[aid] = csv_file

    print(f"Found {len(sample_per_action)} unique action IDs.\n")

    rows = []
    for aid in sorted(sample_per_action.keys()):
        csv_path = sample_per_action[aid]
        skeleton = read_etri_csv(csv_path)

        if skeleton is None:
            print(f"  {aid}: ⚠️  Could not read {csv_path.name}")
            continue

        stats = compute_stats(skeleton)
        stats["action_id"] = aid
        rows.append(stats)

    df = pd.DataFrame(rows).set_index("action_id")

    # ----------------------------------------------------------------
    # Print sorted tables to identify each target class
    # ----------------------------------------------------------------
    print("=" * 65)
    print("SLEEP candidates — lowest avg_hip_y (person is lying down)")
    print("=" * 65)
    print(df[["avg_hip_y", "spine_std", "n_frames"]].sort_values("avg_hip_y").head(15).to_string())

    print()
    print("=" * 65)
    print("EAT/DRINK candidates — lowest wrist_to_head (arms near face)")
    print("=" * 65)
    print(df[["wrist_to_head", "avg_hip_y", "n_frames"]].sort_values("wrist_to_head").head(15).to_string())

    print()
    print("=" * 65)
    print("WALK candidates — highest foot_range (feet moving most)")
    print("=" * 65)
    print(df[["foot_range", "spine_std", "n_frames"]].sort_values("foot_range", ascending=False).head(15).to_string())

    print()
    print("=" * 65)
    print("Full table (all action IDs)")
    print("=" * 65)
    print(df[["avg_hip_y", "wrist_to_head", "foot_range", "spine_std", "n_frames"]].to_string())

    # Save to CSV for easier inspection
    out_path = Path(r"D:\Year 4 UNI\Sava\etri_class_stats.csv")
    df.to_csv(out_path)
    print(f"\n✅ Full stats saved to: {out_path}")
    print("\nLook at the tables above to identify WALK/EAT/DRINK/SLEEP action IDs,")
    print("then update ACTION_MAP in extract_keypoints_etri.py accordingly.")


if __name__ == "__main__":
    main()
