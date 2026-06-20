"""
Run this on the Raspberry Pi to verify the MPU-6050 is wired and reading correctly
before running the full pipeline.

  python test_accelerometer.py

Expected output when flat/still: magnitude ≈ 1.0g (gravity).
Expected output when shaken hard: magnitude spikes well above 2g.
"""

import math
import time
import sys

try:
    import smbus2
except ImportError:
    print("ERROR: smbus2 not installed.  Run:  pip install smbus2")
    sys.exit(1)

I2C_BUS  = 1
I2C_ADDR = 0x68
PWR_MGMT_1   = 0x6B
ACCEL_XOUT_H = 0x3B
SCALE = 16384.0  # LSB/g at ±2g full-scale range

try:
    bus = smbus2.SMBus(I2C_BUS)
    bus.write_byte_data(I2C_ADDR, PWR_MGMT_1, 0)  # wake sensor
    print(f"MPU-6050 found at I2C address 0x{I2C_ADDR:02X} on bus {I2C_BUS}")
except Exception as e:
    print(f"ERROR: Could not connect to MPU-6050 — {e}")
    print("Check wiring: SDA→GPIO2, SCL→GPIO3, VCC→3.3V, GND→GND")
    print("Also verify I2C is enabled:  sudo raspi-config  → Interface Options → I2C")
    sys.exit(1)


def read_magnitude():
    data = bus.read_i2c_block_data(I2C_ADDR, ACCEL_XOUT_H, 6)

    def signed(hi, lo):
        v = (hi << 8) | lo
        return v - 65536 if v > 32767 else v

    ax = signed(data[0], data[1]) / SCALE
    ay = signed(data[2], data[3]) / SCALE
    az = signed(data[4], data[5]) / SCALE
    return ax, ay, az, math.sqrt(ax*ax + ay*ay + az*az)


print("\nReading accelerometer (Ctrl+C to stop)...\n")
print(f"{'Time':>6}  {'X':>7}  {'Y':>7}  {'Z':>7}  {'|a|':>7}")
print("-" * 45)

start = time.time()
try:
    while True:
        ax, ay, az, mag = read_magnitude()
        t = time.time() - start
        flag = "  *** FALL THRESHOLD ***" if mag > 2.5 else ""
        print(f"{t:6.1f}s  {ax:+6.3f}g  {ay:+6.3f}g  {az:+6.3f}g  {mag:6.3f}g{flag}")
        time.sleep(0.5)
except KeyboardInterrupt:
    print("\nDone.")
finally:
    bus.close()
