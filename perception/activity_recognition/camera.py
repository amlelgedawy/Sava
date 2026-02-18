import cv2
import time
from config import *
from detector import detect_person
from pose_estimator import estimate_pose


def initialize_camera():
    cap = cv2.VideoCapture(CAMERA_INDEX, cv2.CAP_DSHOW)

    if not cap.isOpened():
        raise Exception("❌ Error: Cannot open camera")

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)

    return cap


def initialize_recorder():
    if not ENABLE_RECORDING:
        return None

    fourcc = cv2.VideoWriter_fourcc(*'XVID')
    out = cv2.VideoWriter(
        OUTPUT_VIDEO_NAME,
        fourcc,
        TARGET_FPS,
        (FRAME_WIDTH, FRAME_HEIGHT)
    )
    return out


def run_camera():
    cap = initialize_camera()
    recorder = initialize_recorder()

    print("✅ Camera started successfully.")
    print("Press 'q' to quit.")

    prev_time = 0

    while True:
        ret, frame = cap.read()

        if not ret:
            print("❌ Failed to grab frame.")
            break

        # Resize
        frame = cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT))

        # -------------------------------
        # 1️⃣ Person Detection (YOLO)
        # -------------------------------
        frame = detect_person(frame)

        # -------------------------------
        # 2️⃣ Pose Estimation (MediaPipe)
        # -------------------------------
        frame, keypoints = estimate_pose(frame)

        # Optional debug
        if keypoints:
            print(f"Detected {len(keypoints)} keypoints")

        # -------------------------------
        # FPS Control
        # -------------------------------
        current_time = time.time()
        elapsed = current_time - prev_time

        if elapsed < 1.0 / TARGET_FPS:
            continue

        fps = 1.0 / elapsed if elapsed > 0 else 0
        prev_time = current_time

        # FPS Display
        cv2.putText(
            frame,
            f"FPS: {int(fps)}",
            (10, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            1,
            (0, 255, 0),
            2
        )

        # Display
        cv2.imshow("Alzheimer Monitoring - Phase 2", frame)

        # Record if enabled
        if recorder:
            recorder.write(frame)

        # Exit on 'q'
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()

    if recorder:
        recorder.release()

    cv2.destroyAllWindows()
    print("🛑 Camera stopped cleanly.")