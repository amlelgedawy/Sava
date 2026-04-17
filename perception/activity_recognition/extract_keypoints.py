import os
import cv2
import numpy as np
from tqdm import tqdm

from pose_estimator import PoseEstimator


# ====== CONFIG ======
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

RAW_VIDEOS_PATH = os.path.join(BASE_DIR, "data", "raw_videos")
SAVE_PATH = os.path.join(BASE_DIR, "data", "keypoints")
MIN_FRAMES_REQUIRED = 3  # skip very short videos


# Create save directory if not exists
os.makedirs(SAVE_PATH, exist_ok=True)


pose_model = PoseEstimator()


def normalize_keypoints(keypoints):
    """
    Normalize pose by subtracting hip center (landmark 23 & 24 average)
    """
    left_hip = keypoints[23]
    right_hip = keypoints[24]
    hip_center = (left_hip + right_hip) / 2

    keypoints = keypoints - hip_center
    return keypoints


def process_video(video_path):
    cap = cv2.VideoCapture(video_path)
    sequence = []

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        _, keypoints = pose_model.extract(frame, draw=False)

        # Normalize
        keypoints = normalize_keypoints(keypoints)

        sequence.append(keypoints)

    cap.release()

    return np.array(sequence, dtype=np.float32)


def main():
    print("Starting Keypoint Extraction...\n")

    for action in os.listdir(RAW_VIDEOS_PATH):

        action_path = os.path.join(RAW_VIDEOS_PATH, action)

        if not os.path.isdir(action_path):
            continue

        print(f"\nProcessing action: {action}")

        for video_name in tqdm(os.listdir(action_path)):

            video_path = os.path.join(action_path, video_name)

            sequence = process_video(video_path)

            if len(sequence) < MIN_FRAMES_REQUIRED:
                print(f"Skipped {video_name} (too short)")
                continue

            save_name = f"{action}_{video_name.split('.')[0]}.npy"
            save_path = os.path.join(SAVE_PATH, save_name)

            np.save(save_path, sequence)

    print("\nKeypoint extraction completed successfully.")


if __name__ == "__main__":
    main()