from pir_sensor import read_pir
from door_sensor import read_door
from send_data import send_to_backend
import time

print("IoT System Started")

while True:
    motion = read_pir()
    door = read_door()

    if motion or door:
        send_to_backend(motion, door)
        print("Data sent:", motion, door)

    time.sleep(2)
