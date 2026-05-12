from datetime import datetime, date
from mongoengine import Document, StringField, DateTimeField, ReferenceField

from apps.monitoring.models.user import User


class Patient(Document):
    GENDER_MALE = "MALE"
    GENDER_FEMALE = "FEMALE"
    GENDER_CHOICES = (GENDER_MALE, GENDER_FEMALE)

    name = StringField(required=True, max_length=200)
    date_of_birth = DateTimeField(required=True)
    gender = StringField(required=True, choices=GENDER_CHOICES)
    current_medication = StringField()
    face_video_path = StringField()
    created_by = ReferenceField(User, required=True)

    created_at = DateTimeField(default=datetime.now)
    updated_at = DateTimeField(default=datetime.now)

    meta = {
        "collection": "patients",
        "indexes": ["-created_at"],
    }

    @property
    def age(self) -> int:
        today = date.today()
        dob = self.date_of_birth
        if isinstance(dob, datetime):
            dob = dob.date()
        return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


class PatientRelativeLink(Document):
    ROLE_PRIMARY = "PRIMARY"
    ROLE_SECONDARY = "SECONDARY"
    ROLE_CHOICES = (ROLE_PRIMARY, ROLE_SECONDARY)

    patient = ReferenceField(Patient, required=True)
    relative = ReferenceField(User, required=True)
    role_type = StringField(required=True, choices=ROLE_CHOICES)

    created_at = DateTimeField(default=datetime.now)

    meta = {
        "collection": "patient_relative_links",
        "indexes": [
            {"fields": ["patient", "relative"], "unique": True},
            "patient",
            "relative",
        ],
    }
