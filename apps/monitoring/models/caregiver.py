from datetime import datetime
from mongoengine import (Document, EmbeddedDocument, EmbeddedDocumentListField,
    StringField, DateTimeField, ReferenceField)

from apps.monitoring.models.user import User
from apps.monitoring.models.patient import Patient


class CaregiverContract(Document):
    STATUS_PENDING = "PENDING"
    STATUS_ACTIVE = "ACTIVE"
    STATUS_DECLINED = "DECLINED"
    STATUS_ENDED = "ENDED"
    STATUS_CHOICES = (STATUS_PENDING, STATUS_ACTIVE, STATUS_DECLINED, STATUS_ENDED)

    patient = ReferenceField(Patient, required=True)
    caregiver = ReferenceField(User, required=True)
    offered_by = ReferenceField(User, required=True)
    status = StringField(required=True, default=STATUS_PENDING, choices=STATUS_CHOICES)

    created_at = DateTimeField(default=datetime.now)
    accepted_at = DateTimeField()
    ended_at = DateTimeField()

    meta = {
        "collection": "caregiver_contracts",
        "indexes": [
            "patient",
            "caregiver",
            "status",
            "-created_at",
        ],
    }


class MedicationEntry(EmbeddedDocument):
    medicine_name = StringField(required=True)
    time_to_consume = StringField(required=True)
    dosage = StringField()
    notes = StringField()


class MedicationSchedule(Document):
    patient = ReferenceField(Patient, required=True)
    entries = EmbeddedDocumentListField(MedicationEntry)
    created_by = ReferenceField(User, required=True)
    updated_by = ReferenceField(User)

    created_at = DateTimeField(default=datetime.now)
    updated_at = DateTimeField(default=datetime.now)

    meta = {
        "collection": "medication_schedules",
        "indexes": ["patient"],
    }
