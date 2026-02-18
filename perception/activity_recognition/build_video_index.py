import os
import csv
from pathlib import Path

# ✅ Your dataset root (confirmed)
DATASET_ROOT = Path(r"D:\Year 4 UNI\ADL dataset\data")

# ✅ Where we will save the index file inside your SAVA project
OUTPUT_CSV = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\video_index.csv")

# ✅ Activity folder names in the dataset -> Our labels
ACTIVITY_TO_LABEL = {
    "Eat.Snack": "EAT",
    "Eat.Useutensil": "EAT",
    "Drink.Frombottle": "DRINK",
    "Drink.Fromcup": "DRINK",
    "Nap": "NAP",
    "Lay.Onbed": "SLEEP",
}

VIDEO_EXTS = {".mp4", ".avi", ".mov", ".mkv"}


def find_videos_for_subject(subject_dir: Path):
    """
    subject_dir example: .../data/p101
    We search inside it for activity folders like Eat.Snack, Drink.Fromcup, etc.
    """
    rows = []

    for activity_name, label in ACTIVITY_TO_LABEL.items():
        activity_path = subject_dir / activity_name
        if not activity_path.exists():
            continue

        # Find all videos under this activity folder (nested folders included)
        for video_path in activity_path.rglob("*"):
            if video_path.is_file() and video_path.suffix.lower() in VIDEO_EXTS:
                rows.append((label, str(video_path)))

    return rows


def main():
    if not DATASET_ROOT.exists():
        raise FileNotFoundError(f"Dataset root not found: {DATASET_ROOT}")

    # Ensure output folder exists
    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)

    all_rows = []

    # Subject folders are like p101, p102, ...
    for subject in sorted(DATASET_ROOT.iterdir()):
        if subject.is_dir() and subject.name.lower().startswith("p"):
            all_rows.extend(find_videos_for_subject(subject))

    # Remove duplicates (just in case)
    all_rows = list(dict.fromkeys(all_rows))

    # Write CSV
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["label", "video_path"])
        writer.writerows(all_rows)

    # Print summary
    counts = {}
    for label, _ in all_rows:
        counts[label] = counts.get(label, 0) + 1

    print("✅ Saved:", OUTPUT_CSV)
    print("Total videos:", len(all_rows))
    for k in sorted(counts.keys()):
        print(f"{k}: {counts[k]}")


if __name__ == "__main__":
    main()