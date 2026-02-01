import RPi.GPIO as GPIO
from config import DOOR_PIN

GPIO.setmode(GPIO.BCM)
GPIO.setup(DOOR_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

def read_door():
    return GPIO.input(DOOR_PIN) == 0
