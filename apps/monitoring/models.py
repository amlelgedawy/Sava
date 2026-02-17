from datetime import datetime
from mongoengine import (Document, EmbeddedDocument,
    StringField, EmailField, DateTimeField, BooleanField,
    ReferenceField, ListField, DictField, FloatField)


## USERS

class User(Document):
    ROLE_PATIENT = "PATIENT"
    ROLE_CAREGIVER = "CAREGIVER"
    ROLE_CHOICES = (ROLE_PATIENT, ROLE_CAREGIVER)
    
    name = StringField(required = True)
    email = EmailField(required = True, unique = True)
    role = StringField(required = True, choices = ROLE_CHOICES)
    
    created_at = DateTimeField(default= datetime.now)
    updated_at = DateTimeField(default=  datetime.now)
    
    meta = {"collection": "users"}
    
        
## P->C M TO M

class PatientCaregiverLink(Document):
    patient = ReferenceField(User, required = True)
    caregiver = ReferenceField(User, required = True)
    
    created_at = DateTimeField(default= datetime.now)
    
    meta= {"collection": "patient_caregiver_links",
        "indexes": [
            {"fields": ["patient", "caregiver"], "unique": True},
            "patient",
            "caregiver",
        ],
    }
    
## EVENTS

class Event(Document):
    TYPE_FACE = "FACE"
    TYPE_FALL = "FALL"
    TYPE_OBJECT = "OBJECT"
    TYPE_CHOICES = (TYPE_FACE, TYPE_OBJECT, TYPE_FALL)
    
    patient = ReferenceField(User, required = True)
    event_type = StringField(required = True, choices = TYPE_CHOICES)
    
    confidence = FloatField(required = True, min_value=0.0, max_value=1.0)
    payload = DictField()
    
    created_at = DateTimeField(default= datetime.now)
    
    meta = {"collection":"events",
            "indexes": ["patient", "event_type", "-created_at"],
            }
    

##ALERTS

class Alert(Document):
    STATUS_NEW = "NEW"
    STATUS_SEEN = "SEEN"
    STATUS_CHOICES = (STATUS_NEW, STATUS_SEEN)
    
    patient = ReferenceField(User, required = True)
    caregiver =ReferenceField(User, required = True)
    event = ReferenceField(Event, required = True)

    
    alert_type = StringField(required = True)
    message = StringField(required = True)
    status = StringField(default = STATUS_NEW, choices = STATUS_CHOICES)
    
    
    created_at = DateTimeField(default = datetime.now)
    
    meta = {
        "collection": "alerts",
        "indexes": [
            "patient",
            "caregiver",
            "alert_type",
            "-created_at",
        ],
    }
    
    