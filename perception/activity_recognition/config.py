import os as _os

# Camera Settings
# Set CAMERA_URL env var on Pi to the IP Webcam stream, e.g.:
#   export CAMERA_URL="http://192.168.1.x:8080/video"
# Falls back to local webcam (index 0) when the variable is not set.
_cam_url = _os.environ.get("CAMERA_URL", "")
CAMERA_INDEX = _cam_url if _cam_url else 0

# True = Pi / headless server (no cv2.imshow). False = dev laptop (shows window).
HEADLESS_MODE = True

FRAME_WIDTH  = 640
FRAME_HEIGHT = 480
TARGET_FPS   = 15

# Recording Settings
ENABLE_RECORDING  = False
OUTPUT_VIDEO_NAME = "output.avi"

# Wandering Detection Settings
# Person must be walking for this many seconds before tortuosity is evaluated
WANDERING_MIN_WALK_SECONDS = 300        # 5 minutes
# Ratio of total path length / net displacement — above this = wandering
WANDERING_TORTUOSITY_THRESHOLD = 3.0
# How many frames of position history to keep (5 min @ 15 fps)
WANDERING_BUFFER_FRAMES = TARGET_FPS * WANDERING_MIN_WALK_SECONDS  # 4500 frames

# Pain Detection
PAIN_MODEL_PATH = _os.path.join(
    _os.path.dirname(_os.path.abspath(__file__)),
    "..", "emotion_recognition", "pain_efficientnet_b0.pt"
)
PAIN_FRAME_INTERVAL  = 3    # run pain detector every N frames (~5 FPS at 15 FPS capture)
PAIN_BASELINE_FRAMES = 20   # frames used to calibrate neutral PSPI
PAIN_ALERT_THRESH    = 30   # pain % above which alert fires
PAIN_ALERT_PERSIST   = 10   # consecutive frames above thresh before alert triggers (~0.67 s)

# Accelerometer (MPU-6050 via I2C — wrist placement on Raspberry Pi 5)
ACCEL_ENABLED              = True
ACCEL_I2C_BUS              = 1       # Raspberry Pi I2C bus
ACCEL_I2C_ADDR             = 0x68   # MPU-6050 default I2C address
ACCEL_SAMPLE_RATE_HZ       = 100    # polling rate in background thread
ACCEL_FREEFALL_THRESHOLD_G = 0.6    # |a| below this = free-fall phase
ACCEL_IMPACT_THRESHOLD_G   = 1.1    # |a| above this after free-fall = impact confirmed
ACCEL_STANDALONE_G         = 1.1    # |a| above this fires alert without camera
ACCEL_FREEFALL_MIN_MS      = 40     # free-fall must last at least this long (ms)
ACCEL_IMPACT_WINDOW_MS     = 500    # impact must follow free-fall within this window (ms)
ACCEL_IMPACT_FLAG_SEC      = 8.0    # how long impact flags stay True after event