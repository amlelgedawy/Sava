from datetime import datetime, timedelta
from django.conf import settings

from apps.monitoring.models import Alert, Event, User
from apps.accounts.services.user_service import UserService


class AlertService:
    @staticmethod
    def _cooldown_passed(patient: User, alert_type: str) -> bool:
        last = Alert.objects(patient=patient, alert_type=alert_type).order_by("-created_at").first()
        if not last:
            return True
        cooldown = timedelta(seconds=settings.ALERT_COOLDOWN_SECONDS)
        return (datetime.utcnow() - last.created_at) >= cooldown

    @staticmethod
    def should_alert_for_event(event: Event) -> bool:
        # Check for different event types that can trigger alerts
        if event.event_type == Event.TYPE_FACE:
            # Legacy face events - check if unknown person
            known = bool(event.payload.get("known", True))
            if known:
                return False
            if event.confidence < settings.FACE_UNKNOWN_THRESHOLD:
                return False
            alert_type = "UNKNOWN_FACE"
            
        elif event.event_type == Event.TYPE_PERSON_ENTER:
            # Person enter events - check if unknown person
            status = event.payload.get("status", "")
            if status in ["IDENTIFIED", "PROCESSING"]:
                return False  # Don't alert for known persons
            alert_type = "UNKNOWN_PERSON_ENTER"
            
        elif event.event_type == Event.TYPE_OBJECT:
            # Object events - check if dangerous object
            object_class = event.payload.get("object_class", "")
            is_dangerous = event.payload.get("is_dangerous", False)
            
            if not is_dangerous:
                return False  # Only alert for dangerous objects
            
            alert_type = "DANGEROUS_OBJECT"
            
        else:
            # Other event types don't trigger alerts
            return False

        # Check cooldown
        if not AlertService._cooldown_passed(event.patient, alert_type):
            return False

        # Check if patient has caregivers
        caregivers = UserService.get_caregivers_for_patient(str(event.patient.id))
        if not caregivers:
            return False

        return True

    @staticmethod
    def create_alerts_for_event(event: Event) -> list[Alert]:
        caregivers = UserService.get_caregivers_for_patient(str(event.patient.id))

        # Determine alert type and message
        if event.event_type == Event.TYPE_FACE:
            alert_type = "UNKNOWN_FACE"
            message = "Unknown person detected by face recognition."
        elif event.event_type == Event.TYPE_PERSON_ENTER:
            alert_type = "UNKNOWN_PERSON_ENTER"
            message = "Unknown person entered the monitored area."
        elif event.event_type == Event.TYPE_OBJECT:
            alert_type = "DANGEROUS_OBJECT"
            object_class = event.payload.get("object_class", "unknown object")
            message = f"Dangerous object detected: {object_class}. Patient may be at risk."
        else:
            alert_type = event.event_type
            message = f"Event: {event.event_type}"

        alerts = []
        for cg in caregivers:
            alerts.append(
                Alert(
                    patient=event.patient,
                    caregiver=cg,
                    event=event,
                    alert_type=alert_type,
                    message=message,
                    status=Alert.STATUS_NEW,
                    created_at=datetime.utcnow(),
                ).save()
            )
        return alerts
