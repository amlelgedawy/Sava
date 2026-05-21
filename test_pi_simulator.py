"""
Pi Simulator
------------
Uses laptop webcam to simulate a Raspberry Pi pushing frames to the SAVA backend.
Run this in parallel with `python manage.py runserver` to test the live stream
and AI detection pipeline locally.

Usage:
    python test_pi_simulator.py

Press Ctrl+C to stop.
"""

import time
import requests
import cv2

BACKEND = "http://localhost:8000/api/stream/push-frame"
API_KEY = "bkjjbvjxs566t7sycgvuc6s78isb8@@hbbvgchcg"
PATIENT_ID = "6a09bbd515aa4df8cf497641"  # change to your patient _id
FPS = 5


def main() -> None:
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        raise RuntimeError("Could not open webcam (index 0).")

    interval = 1.0 / FPS
    print(f"[PiSim] Streaming to {BACKEND} at {FPS} FPS for patient {PATIENT_ID}")

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                time.sleep(0.1)
                continue

            ok, buf = cv2.imencode(".jpg", frame)
            if not ok:
                continue

            try:
                resp = requests.post(
                    BACKEND,
                    headers={"X-Api-Key": API_KEY},
                    data={"patient_id": PATIENT_ID},
                    files={"frame": ("frame.jpg", buf.tobytes(), "image/jpeg")},
                    timeout=5,
                )
                print(f"[PiSim] {resp.status_code}", end="\r")
            except Exception as e:
                print(f"[PiSim] error: {e}")

            time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[PiSim] stopped")
    finally:
        cap.release()


if __name__ == "__main__":
    main()
