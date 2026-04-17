"""
toilet_camera.py
----------------
Monitors a camera pointed at the bathroom door.
Detects when the door is closed (patient inside) and starts a timer.
When the door opens, stops the timer and alerts if duration exceeded threshold.

State machine:
    OPEN  → door is open / patient not inside
    CLOSED → door is closed / patient inside (timer running)

Run standalone:
    python perception/toilet_monitor/toilet_camera.py

Or import and call run_toilet_monitor() from another module.
"""

import cv2
import time
import datetime
import numpy as np
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TOILET_CAMERA_INDEX     = 1          # camera index for the door-facing camera
ALERT_THRESHOLD_MINUTES = 30         # alert if door closed for longer than this
FRAME_WIDTH             = 640
FRAME_HEIGHT            = 480
TARGET_FPS              = 10         # lower FPS is fine — we only need motion detection

# Frame differencing sensitivity (0–255). Lower = more sensitive.
MOTION_THRESHOLD        = 25         # pixel intensity diff to count as motion
MOTION_PIXEL_RATIO      = 0.01       # fraction of pixels that must change → motion event

# How many consecutive "closed" frames before we confirm door is closed
CONFIRM_CLOSED_FRAMES   = 30         # ~3 seconds at 10 fps
CONFIRM_OPEN_FRAMES     = 30

# Log file
LOG_PATH = Path(r"D:\Year 4 UNI\Sava\logs\toilet_log.txt")


# ---------------------------------------------------------------------------
# Door state machine
# ---------------------------------------------------------------------------
class DoorMonitor:
    """
    Uses background subtraction to detect whether the bathroom door is open or closed.

    Calibration:
        The first CALIBRATION_FRAMES frames are used to learn the background
        (what the scene looks like with the door OPEN = normal resting state).
        A significant change from that background = door CLOSED.
    """

    CALIBRATION_FRAMES = 60   # ~6 seconds at 10 fps

    def __init__(self):
        self._bg_subtractor  = cv2.createBackgroundSubtractorMOG2(
            history=200, varThreshold=40, detectShadows=False
        )
        self._state          = "OPEN"       # current confirmed state
        self._pending        = "OPEN"       # candidate state (must persist to confirm)
        self._pending_frames = 0
        self._door_closed_at = None         # timestamp when door closed
        self._calibrated     = False
        self._calib_count    = 0
        self._alert_fired    = False        # prevent repeated alerts per session

    def update(self, frame):
        """
        Process one frame. Returns (state, elapsed_seconds_or_None, alert_triggered).
        state: "OPEN" or "CLOSED"
        elapsed: seconds door has been closed (only when CLOSED), else None
        alert_triggered: True if threshold just crossed this frame
        """
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (21, 21), 0)

        fg_mask = self._bg_subtractor.apply(gray)

        # Count fraction of changed pixels
        motion_ratio = np.count_nonzero(fg_mask > MOTION_THRESHOLD) / fg_mask.size

        # Calibration phase — just learn background
        if self._calib_count < self.CALIBRATION_FRAMES:
            self._calib_count += 1
            return "CALIBRATING", None, False

        # Determine candidate state from motion
        candidate = "CLOSED" if motion_ratio > MOTION_PIXEL_RATIO else "OPEN"

        # Require N consecutive frames before confirming a state change
        confirm_needed = CONFIRM_CLOSED_FRAMES if candidate == "CLOSED" else CONFIRM_OPEN_FRAMES

        if candidate == self._pending:
            self._pending_frames += 1
        else:
            self._pending        = candidate
            self._pending_frames = 1

        if self._pending_frames >= confirm_needed and candidate != self._state:
            self._state = candidate
            if self._state == "CLOSED":
                self._door_closed_at = time.time()
                self._alert_fired    = False
                print(f"[{_ts()}] 🚪 Door CLOSED — timer started")
            else:
                if self._door_closed_at is not None:
                    duration = (time.time() - self._door_closed_at) / 60
                    print(f"[{_ts()}] 🚪 Door OPEN — patient was inside for {duration:.1f} min")
                    _log(f"Door opened after {duration:.1f} minutes")
                self._door_closed_at = None
                self._alert_fired    = False

        # Compute elapsed time and check alert threshold
        elapsed       = None
        alert_fired   = False

        if self._state == "CLOSED" and self._door_closed_at is not None:
            elapsed = time.time() - self._door_closed_at
            if elapsed >= ALERT_THRESHOLD_MINUTES * 60 and not self._alert_fired:
                self._alert_fired = True
                alert_fired       = True
                msg = f"⚠️  Patient in bathroom for {elapsed/60:.1f} minutes!"
                print(f"[{_ts()}] 🚨 ALERT: {msg}")
                _log(f"ALERT: {msg}")

        return self._state, elapsed, alert_fired


def _ts():
    return datetime.datetime.now().strftime("%H:%M:%S")


def _log(message):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_PATH, "a") as f:
        f.write(f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}\n")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def run_toilet_monitor():
    cap = cv2.VideoCapture(TOILET_CAMERA_INDEX, cv2.CAP_DSHOW)
    if not cap.isOpened():
        raise Exception(
            f"❌ Cannot open toilet camera (index {TOILET_CAMERA_INDEX}). "
            "Check TOILET_CAMERA_INDEX in toilet_camera.py."
        )

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)

    monitor   = DoorMonitor()
    frame_interval = 1.0 / TARGET_FPS
    prev_time = 0

    print("✅ Toilet monitor started.")
    print(f"   Alert threshold: {ALERT_THRESHOLD_MINUTES} minutes")
    print("Press 'q' to quit.\n")

    while True:
        ret, frame = cap.read()
        if not ret:
            print("❌ Failed to grab frame from toilet camera.")
            break

        current_time = time.time()
        if current_time - prev_time < frame_interval:
            continue
        prev_time = current_time

        state, elapsed, alert = monitor.update(frame)

        # Build overlay
        if state == "CALIBRATING":
            status_text  = "Calibrating..."
            status_color = (180, 180, 180)
        elif state == "CLOSED":
            mins = elapsed / 60 if elapsed else 0
            status_text  = f"OCCUPIED  {mins:.1f} min"
            status_color = (0, 165, 255)   # orange
        else:
            status_text  = "VACANT"
            status_color = (0, 200, 0)

        display = frame.copy()
        cv2.putText(display, status_text, (10, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.2, status_color, 3)

        if alert or (state == "CLOSED" and elapsed and elapsed >= ALERT_THRESHOLD_MINUTES * 60):
            cv2.putText(display, "🚨 CAREGIVER ALERT", (10, 85),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 255), 3)

        cv2.putText(display, f"Threshold: {ALERT_THRESHOLD_MINUTES} min", (10, FRAME_HEIGHT - 15),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)

        cv2.imshow("SAVA - Toilet Monitor", display)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()
    print("🛑 Toilet monitor stopped.")


if __name__ == "__main__":
    run_toilet_monitor()
