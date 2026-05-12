from datetime import datetime
from apps.monitoring.models import Event, User

class EventService:
    @staticmethod
    def create_event(patient: User, event_type: str, confidence: float, payload: dict) -> Event:
        return Event(
            patient=patient,
            event_type=event_type,
            confidence=float(confidence),
            payload=payload or {},
            created_at=datetime.utcnow(),
        ).save()
