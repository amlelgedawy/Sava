"""
Quick standalone test for MPU-6050 accelerometer via I2C.
Run on the Pi:  python test_accelerometer.py
"""

import math
import time

I2C_BUS  = 1
I2C_ADDR = 0x68
PWR_MGMT_1   = 0x6B
ACCEL_XOUT_H = 0x3B
SCALE = 16384.0  # LSB/g at ±2g

try:
    import smbus2
except ImportError:
    print("smbus2 not installed — run: pip install smbus2")
    raise SystemExit(1)

bus = smbus2.SMBus(I2C_BUS)

# Wake the MPU-6050 (register 0x6B = 0 disables sleep mode)
bus.write_byte_data(I2C_ADDR, PWR_MGMT_1, 0)
time.sleep(0.1)
print(f"MPU-6050 woken up on bus {I2C_BUS}, address 0x{I2C_ADDR:02X}\n")
print(f"{'Time':>8}  {'Ax (g)':>8}  {'Ay (g)':>8}  {'Az (g)':>8}  {'|a| (g)':>8}")
print("-" * 52)

def read_accel():
    data = bus.read_i2c_block_data(I2C_ADDR, ACCEL_XOUT_H, 6)
    def s16(hi, lo):
        v = (hi << 8) | lo
        return v - 65536 if v > 32767 else v
    ax = s16(data[0], data[1]) / SCALE
    ay = s16(data[2], data[3]) / SCALE
    az = s16(data[4], data[5]) / SCALE
    return ax, ay, az

start = time.time()
try:
    while True:
        ax, ay, az = read_accel()
        mag = math.sqrt(ax**2 + ay**2 + az**2)
        elapsed = time.time() - start
        print(f"{elapsed:8.2f}  {ax:8.3f}  {ay:8.3f}  {az:8.3f}  {mag:8.3f}")
        time.sleep(0.5)
except KeyboardInterrupt:
    print("\nStopped.")
finally:
    bus.close()
