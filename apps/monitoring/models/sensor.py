from datetime import datetime
from mongoengine import Document, ReferenceField, FloatField, DateTimeField

from apps.monitoring.models.patient import Patient


class SensorReading(Document):
    """
    One reading pushed by the Raspberry Pi alongside a video frame.
    All sensor fields are optional — Pi may not have all sensors attached.
    """

    patient = ReferenceField(Patient, required=True)

    hrv = FloatField()          # heart-rate variability (ms or bpm depending on sensor)
    accel_x = FloatField()      # accelerometer X axis (g)
    accel_y = FloatField()      # accelerometer Y axis (g)
    accel_z = FloatField()      # accelerometer Z axis (g)

    created_at = DateTimeField(default=datetime.utcnow)

    meta = {
        "collection": "sensor_readings",
        "indexes": ["patient", "-created_at"],
    }
