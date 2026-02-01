import RPi.GPIO as GPIO
from config import PIR_PIN

GPIO.setmode(GPIO.BCM)
GPIO.setup(PIR_PIN, GPIO.IN)

def read_pir():
    return GPIO.input(PIR_PIN)
