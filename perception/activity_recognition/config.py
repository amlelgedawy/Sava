
# Camera Settings
CAMERA_INDEX = 0  # 0 = default laptop camera

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
