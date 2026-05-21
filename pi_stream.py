import cv2, requests, time, os
from mpu6050 import mpu6050

# Configuration
CAMERA_URL = os.environ.get("CAMERA_URL", "http://192.168.1.3:8080/video")
DJANGO_URL = "https://sava-production.up.railway.app"
PI_API_KEY = "bkjjbvjxs566t7sycgvuc6s78isb8@@hbbvgchcg"
PATIENT_ID = "6a09bbd515aa4df8cf497641"
TARGET_FPS = 15

# Connect to accelerometer
try:
    sensor = mpu6050(0x68)
    accel_ok = True
except:
    accel_ok = False

# Read accelerometer data
def get_accel():
    if not accel_ok: return {"x":0,"y":0,"z":0}
    try: return sensor.get_accel_data()
    except: return {"x":0,"y":0,"z":0}

# Connect to camera
cap = cv2.VideoCapture(CAMERA_URL)
if not cap.isOpened():
    print("Cannot open camera"); exit(1)
print("Camera OK")

# Main loop
while True:
    ret, frame = cap.read()
    if not ret:
        cap = cv2.VideoCapture(CAMERA_URL)
        time.sleep(2)
        continue
    
    # Resize and encode frame
    frame = cv2.resize(frame, (640, 480))
    _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 50])
    
    # Get accelerometer data
    a = get_accel()
    
    # Push frame + sensor data to Railway
    requests.post(
        f"{DJANGO_URL}/api/stream/push-frame",
        headers={"X-Api-Key": PI_API_KEY},
        files={"frame": ("f.jpg", buf.tobytes(), "image/jpeg")},
        data={"patient_id": PATIENT_ID, "accel_x": a["x"], "accel_y": a["y"], "accel_z": a["z"]},
        timeout=3
    )