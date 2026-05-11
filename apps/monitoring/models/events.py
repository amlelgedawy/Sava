from datetime import datetime
from mongoengine import Document, StringField, DateTimeField, FloatField, ReferenceField, DictField

from apps.monitoring.models.user import User
from apps.monitoring.models.patient import Patient
from apps.monitoring.models.tracking import PersonTracking


class Event(Document):
    TYPE_FACE = "FACE"
    TYPE_FALL = "FALL"
    TYPE_OBJECT = "OBJECT"
    TYPE_PERSON_ENTER = "PERSON_ENTER"
    TYPE_PERSON_EXIT = "PERSON_EXIT"
    TYPE_ACTIVITY = "ACTIVITY"
    TYPE_CHOICES = (TYPE_FACE, TYPE_OBJECT, TYPE_FALL, TYPE_PERSON_ENTER, TYPE_PERSON_EXIT, TYPE_ACTIVITY)

    patient = ReferenceField(Patient, required=True)
    event_type = StringField(required=True, choices=TYPE_CHOICES)

    confidence = FloatField(required=True, min_value=0.0, max_value=1.0)
    payload = DictField()

    person_tracking = ReferenceField(PersonTracking, required=False)

    created_at = DateTimeField(default=datetime.now)

    meta = {
        "collection": "events",
        "indexes": ["patient", "event_type", "person_tracking", "-created_at"],
    }


class Alert(Document):
    STATUS_NEW = "NEW"
    STATUS_SEEN = "SEEN"
    STATUS_DISMISSED = "DISMISSED"
    STATUS_CHOICES = (STATUS_NEW, STATUS_SEEN, STATUS_DISMISSED)

    patient = ReferenceField(Patient, required=True)
    recipient = ReferenceField(User, required=True)
    event = ReferenceField(Event, required=True)

    alert_type = StringField(required=True)
    message = StringField(required=True)
    status = StringField(default=STATUS_NEW, choices=STATUS_CHOICES)

    created_at = DateTimeField(default=datetime.now)

    meta = {
        "collection": "alerts",
        "indexes": [
            "patient",
            "recipient",
            "alert_type",
            "-created_at",
        ],
    }
