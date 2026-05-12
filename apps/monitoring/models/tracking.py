from datetime import datetime
from mongoengine import (Document, StringField, DateTimeField, FloatField,
    IntField, ReferenceField, ListField, DictField)

from apps.monitoring.models.patient import Patient


class PersonTracking(Document):
    STATUS_NEW = "NEW"
    STATUS_PROCESSING = "PROCESSING"
    STATUS_IDENTIFIED = "IDENTIFIED"
    STATUS_UNKNOWN = "UNKNOWN"
    STATUS_CHOICES = (STATUS_NEW, STATUS_PROCESSING, STATUS_IDENTIFIED, STATUS_UNKNOWN)

    patient = ReferenceField(Patient, required=True)
    tracking_id = StringField(required=True, unique=True)
    status = StringField(default=STATUS_NEW, choices=STATUS_CHOICES)

    person_name = StringField()
    confidence = FloatField(min_value=0.0, max_value=1.0)

    first_seen = DateTimeField(default=datetime.now)
    last_seen = DateTimeField(default=datetime.now)
    frame_count = IntField(default=1)

    face_embedding = ListField(FloatField())
    last_bbox = DictField()

    meta = {
        "collection": "person_tracking",
        "indexes": [
            "patient",
            "tracking_id",
            "status",
            "-first_seen",
            "-last_seen",
        ],
    }
