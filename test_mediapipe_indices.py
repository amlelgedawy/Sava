import mediapipe as mp

mp_pose = mp.solutions.pose

for i, lm in enumerate(mp_pose.PoseLandmark):
    print(i, lm)