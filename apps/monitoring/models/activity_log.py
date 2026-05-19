from datetime import datetime
from mongoengine import Document, StringField, DateTimeField, FloatField, ReferenceField, DictField

from apps.monitoring.models.patient import Patient


class ActivityLog(Document):
    """
    Lightweight record for normal (non-alert) patient activities.
    Created by ResultProcessor for every AI result that does not warrant an Alert.
    """

    ACTIVITY_CHOICES = (
        "EAT", "DRINK", "SLEEP", "FALL", "WALK",
        "SIT", "STAND", "USE_PHONE", "CHEST_PAIN",
        "DANGEROUS_OBJECT", "UNKNOWN_FACE",
    )

    patient = ReferenceField(Patient, required=True)
    activity = StringField(required=True)
    confidence = FloatField(required=True, min_value=0.0, max_value=1.0)
    source = StringField(required=True, choices=("ACTIVITY_SERVER", "FACE_SERVER", "SENSOR"))
    payload = DictField()
    created_at = DateTimeField(default=datetime.utcnow)

    meta = {
        "collection": "activity_logs",
        "indexes": ["patient", "activity", "-created_at"],
    }
