import os
import time
import threading

import cv2
import requests

try:
    from mpu6050 import mpu6050
except ImportError:
    mpu6050 = None


# Configuration
CAMERA_URL = os.environ.get("CAMERA_URL", "http://192.168.1.4:8080/video")
DJANGO_URL = os.environ.get("DJANGO_URL", "http://192.168.1.3:8000")
PI_API_KEY = os.environ.get("PI_API_KEY", "sava-pi-dev-key")
PATIENT_ID = "6a0e4fc16b309057efb4acde"
TARGET_FPS = 15
JPEG_QUALITY = 50
FRAME_SIZE = (640, 480)


# Connect to accelerometer
try:
    sensor = mpu6050(0x68) if mpu6050 else None
    accel_ok = sensor is not None
except Exception:
    sensor = None
    accel_ok = False


def get_accel():
    if not accel_ok:
        return {"x": 0, "y": 0, "z": 0}
    try:
        return sensor.get_accel_data()
    except Exception:
        return {"x": 0, "y": 0, "z": 0}


# Latest-frame-only capture thread.
#
# cv2.VideoCapture buffers frames from the MJPEG source internally. If the
# send loop ever falls behind, cap.read() starts returning stale frames and
# the visible lag grows over time. This thread does nothing but grab frames
# as fast as the source provides them and keep only the most recent one, so
# the send loop below always works with the freshest frame available.

_latest_frame = None
_frame_lock = threading.Lock()
_running = True


def _capture_loop():
    global _latest_frame
    cap = cv2.VideoCapture(CAMERA_URL)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    while _running:
        ret, frame = cap.read()
        if not ret:
            cap.release()
            time.sleep(2)
            cap = cv2.VideoCapture(CAMERA_URL)
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            continue
        with _frame_lock:
            _latest_frame = frame
    cap.release()


capture_thread = threading.Thread(target=_capture_loop, daemon=True)
capture_thread.start()

print("Waiting for camera...")
while _latest_frame is None:
    time.sleep(0.1)
print("Camera OK")


# Main send loop.
#
# - Reuses one HTTP connection via Session instead of reconnecting per frame.
# - Paces itself to TARGET_FPS so it never races ahead of the network.

session = requests.Session()
interval = 1.0 / TARGET_FPS

try:
    while True:
        loop_start = time.time()

        with _frame_lock:
            frame = _latest_frame.copy()

        frame = cv2.resize(frame, FRAME_SIZE)
        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])

        a = get_accel()

        try:
            r = session.post(
                f"{DJANGO_URL}/api/stream/push-frame",
                headers={"X-Api-Key": PI_API_KEY},
                files={"frame": ("f.jpg", buf.tobytes(), "image/jpeg")},
                data={"patient_id": PATIENT_ID, "accel_x": a["x"], "accel_y": a["y"], "accel_z": a["z"]},
                timeout=3,
            )
            if r.status_code not in (200, 202):
                print(f"Push rejected: {r.status_code} {r.text[:120]}")
        except requests.exceptions.RequestException as e:
            print(f"Push failed: {e}")

        elapsed = time.time() - loop_start
        remaining = interval - elapsed
        if remaining > 0:
            time.sleep(remaining)
except KeyboardInterrupt:
    pass
finally:
    _running = False
    session.close()
