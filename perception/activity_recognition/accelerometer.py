"""
AccelerometerReader — MPU-6050 via smbus2, runs in a background thread.

Fall detection algorithm (wrist placement):
  1. Free-fall : |a| < ACCEL_FREEFALL_THRESHOLD_G for >= ACCEL_FREEFALL_MIN_MS
  2. Impact    : |a| > ACCEL_IMPACT_THRESHOLD_G within ACCEL_IMPACT_WINDOW_MS after free-fall ends
     → sets recent_impact = True for ACCEL_IMPACT_FLAG_SEC seconds

Standalone : |a| > ACCEL_STANDALONE_G at any point
     → sets standalone_fall = True for ACCEL_IMPACT_FLAG_SEC seconds
     (safety net for falls outside camera view)
"""

import math
import threading
import time

from .config import (
    ACCEL_FREEFALL_MIN_MS,
    ACCEL_FREEFALL_THRESHOLD_G,
    ACCEL_I2C_ADDR,
    ACCEL_I2C_BUS,
    ACCEL_IMPACT_FLAG_SEC,
    ACCEL_IMPACT_THRESHOLD_G,
    ACCEL_IMPACT_WINDOW_MS,
    ACCEL_SAMPLE_RATE_HZ,
    ACCEL_STANDALONE_G,
)

_PWR_MGMT_1   = 0x6B
_ACCEL_XOUT_H = 0x3B
_ACCEL_SCALE  = 16384.0   # LSB/g at ±2g full-scale range (MPU-6050 default)


class AccelerometerReader:
    """Reads MPU-6050 in a daemon thread and exposes fall event flags."""

    def __init__(self):
        import smbus2
        self._bus  = smbus2.SMBus(ACCEL_I2C_BUS)
        self._addr = ACCEL_I2C_ADDR
        self._bus.write_byte_data(self._addr, _PWR_MGMT_1, 0)  # wake sensor

        self._lock             = threading.Lock()
        self._running          = False
        self._thread           = None
        self._impact_until     = 0.0  # epoch time until recent_impact is True
        self._standalone_until = 0.0
        self._freefall_start   = None  # epoch time when free-fall phase began
        self._last_xyz         = (0.0, 0.0, 0.0)

    def start(self):
        self._running = True
        self._thread  = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False

    @property
    def recent_impact(self) -> bool:
        """True for ACCEL_IMPACT_FLAG_SEC seconds after a free-fall+impact event."""
        return time.time() < self._impact_until

    @property
    def standalone_fall(self) -> bool:
        """True for ACCEL_IMPACT_FLAG_SEC seconds after a very hard impact (>=ACCEL_STANDALONE_G)."""
        return time.time() < self._standalone_until

    @property
    def xyz(self) -> tuple:
        """Latest (ax, ay, az) reading in g."""
        with self._lock:
            return self._last_xyz

    def _read_magnitude(self) -> float:
        data = self._bus.read_i2c_block_data(self._addr, _ACCEL_XOUT_H, 6)

        def to_signed(hi, lo):
            val = (hi << 8) | lo
            return val - 65536 if val > 32767 else val

        ax = to_signed(data[0], data[1]) / _ACCEL_SCALE
        ay = to_signed(data[2], data[3]) / _ACCEL_SCALE
        az = to_signed(data[4], data[5]) / _ACCEL_SCALE
        with self._lock:
            self._last_xyz = (ax, ay, az)
        return math.sqrt(ax * ax + ay * ay + az * az)

    def _loop(self):
        interval = 1.0 / ACCEL_SAMPLE_RATE_HZ
        while self._running:
            t0 = time.time()
            try:
                mag = self._read_magnitude()
                now = time.time()

                # Standalone: very hard impact fires alert without needing free-fall phase
                if mag > ACCEL_STANDALONE_G:
                    with self._lock:
                        self._standalone_until = now + ACCEL_IMPACT_FLAG_SEC
                        self._impact_until     = now + ACCEL_IMPACT_FLAG_SEC

                # Free-fall → impact sequence
                if mag < ACCEL_FREEFALL_THRESHOLD_G:
                    if self._freefall_start is None:
                        self._freefall_start = now
                else:
                    if self._freefall_start is not None:
                        ff_ms = (now - self._freefall_start) * 1000
                        if (ff_ms >= ACCEL_FREEFALL_MIN_MS and
                                mag > ACCEL_IMPACT_THRESHOLD_G):
                            # Valid free-fall followed immediately by impact
                            with self._lock:
                                self._impact_until = now + ACCEL_IMPACT_FLAG_SEC
                        self._freefall_start = None

            except Exception:
                pass  # I2C glitch — skip this sample

            elapsed = time.time() - t0
            wait    = interval - elapsed
            if wait > 0:
                time.sleep(wait)
