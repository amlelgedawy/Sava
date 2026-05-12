from datetime import datetime
from mongoengine import Document, StringField, EmailField, DateTimeField, FloatField, IntField
from django.contrib.auth.hashers import make_password, check_password


class User(Document):
    ROLE_ADMIN = "ADMIN"
    ROLE_CAREGIVER = "CAREGIVER"
    ROLE_RELATIVE = "RELATIVE"
    ROLE_CHOICES = (ROLE_ADMIN, ROLE_CAREGIVER, ROLE_RELATIVE)

    name = StringField(required=True, max_length=200)
    username = StringField(required=True, unique=True, max_length=50)
    email = EmailField(required=True, unique=True)
    password_hash = StringField(required=True)
    role = StringField(required=True, choices=ROLE_CHOICES)
    face_video_path = StringField()

    # Caregiver-specific fields
    age = IntField()
    national_id = StringField()
    cv_path = StringField()
    salary_per_hour = FloatField()

    created_at = DateTimeField(default=datetime.now)
    updated_at = DateTimeField(default=datetime.now)

    meta = {
        "collection": "users",
        "indexes": ["role", "username"],
    }

    def set_password(self, raw_password: str):
        if not raw_password:
            raise ValueError("Password cannot be empty")
        self.password_hash = make_password(raw_password)
        self.updated_at = datetime.now()

    def check_password(self, raw_password: str) -> bool:
        if not self.password_hash:
            return False
        return check_password(raw_password, self.password_hash)
