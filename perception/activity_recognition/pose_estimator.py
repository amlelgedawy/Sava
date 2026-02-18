import cv2
import mediapipe as mp
import numpy as np
from perception.activity_recognition.data_preprocessing.convert_to_ntu import mediapipe_to_ntu

print("REAL-TIME POSE SEQUENCE COLLECTOR STARTED")

# MediaPipe setup
mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils
pose = mp_pose.Pose()

# Webcam
cap = cv2.VideoCapture(0)

# 🔥 Sequence buffer
sequence = []
WINDOW_SIZE = 64

# SkateFormer "partition=True" expects a specific 24-joint reordering (drops one joint)
# This matches how SkateFormer/feeder_ntu.py builds `new_idx` when partition=True.
NEW_IDX_24 = np.array([
    6, 7, 21, 22,       # right_arm (7,8,22,23) - 1
    10, 11, 23, 24,     # left_arm  (11,12,24,25) - 1
    12, 13, 14, 15,     # right_leg (13,14,15,16) - 1
    16, 17, 18, 19,     # left_leg  (17,18,19,20) - 1
    4, 8, 5, 9,         # h_torso   (5,9,6,10) - 1
    1, 2, 0, 3          # w_torso   (2,3,1,4) - 1
], dtype=np.int64)

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(image_rgb)

    if results.pose_landmarks:
        mp_drawing.draw_landmarks(
            frame,
            results.pose_landmarks,
            mp_pose.POSE_CONNECTIONS
        )

        # Extract 33 landmarks (x, y, z only)
        keypoints = []
        for landmark in results.pose_landmarks.landmark:
            keypoints.append([landmark.x, landmark.y, landmark.z])

        keypoints = np.array(keypoints)  # (33, 3)

        # Add frame to sequence
        sequence.append(keypoints)

        # Keep only last 64 frames (sliding window)
        if len(sequence) > WINDOW_SIZE:
            sequence.pop(0)

        # When we have full 64-frame sequence
        if len(sequence) == WINDOW_SIZE:
            sequence_np = np.array(sequence)  # (64, 33, 3)
            print("64-frame MediaPipe sequence:", sequence_np.shape)

            # 🔥 Convert to NTU 25 joints
            ntu25 = mediapipe_to_ntu(sequence_np)  # (64, 25, 3)

            # 🔥 Apply SkateFormer partition joint selection/reorder → 24 joints
            ntu24 = ntu25[:, NEW_IDX_24, :]  # (64, 24, 3)

            # Add second person (zeros)
            second_person = np.zeros_like(ntu24)

            # Stack persons → (64, 24, 3, 2)
            ntu24 = np.stack([ntu24, second_person], axis=-1)

            # Rearrange to (C, T, V, M) = (3, 64, 24, 2)
            skateformer_input = ntu24.transpose(2, 0, 1, 3)

            print("Final SkateFormer input shape:", skateformer_input.shape)
            print("-" * 50)

            # 🚨 Next step: pass `skateformer_input` into SkateFormer (with index_t)

    cv2.imshow("Pose Estimation - Sequence Mode", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()