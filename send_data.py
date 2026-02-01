import requests
from config import SERVER_URL

def send_to_backend(motion, door):
    data = {
        "motion_detected": motion,
        "door_open": door
    }
    requests.post(SERVER_URL, json=data)
