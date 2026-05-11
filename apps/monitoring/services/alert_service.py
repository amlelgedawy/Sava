from datetime import datetime, timedelta
from django.conf import settings

from apps.monitoring.models import Alert, Event, Patient
from apps.accounts.services.caregiver_service import CaregiverService


class AlertService:
    @staticmethod
    def _cooldown_passed(patient: Patient, alert_type: str) -> bool:
        last = Alert.objects(patient=patient, alert_type=alert_type).order_by("-created_at").first()
        if not last:
            return True
        cooldown = timedelta(seconds=settings.ALERT_COOLDOWN_SECONDS)
        return (datetime.utcnow() - last.created_at) >= cooldown

    @staticmethod
    def should_alert_for_event(event: Event) -> bool:
        if event.event_type == Event.TYPE_FACE:
            known = bool(event.payload.get("known", True))
            if known:
                return False
            if event.confidence < settings.FACE_UNKNOWN_THRESHOLD:
                return False
            alert_type = "UNKNOWN_FACE"

        elif event.event_type == Event.TYPE_PERSON_ENTER:
            evt_status = event.payload.get("status", "")
            if evt_status in ["IDENTIFIED", "PROCESSING"]:
                return False
            alert_type = "UNKNOWN_PERSON_ENTER"

        elif event.event_type == Event.TYPE_OBJECT:
            is_dangerous = event.payload.get("is_dangerous", False)
            if not is_dangerous:
                return False
            alert_type = "DANGEROUS_OBJECT"

        elif event.event_type == Event.TYPE_FALL:
            alert_type = "FALL_DETECTED"

        elif event.event_type == Event.TYPE_ACTIVITY:
            activity = event.payload.get("activity", "")
            if activity not in ["CHEST_PAIN"]:
                return False
            alert_type = f"{activity}_DETECTED"

        else:
            return False

        if not AlertService._cooldown_passed(event.patient, alert_type):
            return False

        recipients = CaregiverService.get_alert_recipients(str(event.patient.id))
        if not recipients:
            return False

        return True

    @staticmethod
    def create_alerts_for_event(event: Event) -> list[Alert]:
        recipients = CaregiverService.get_alert_recipients(str(event.patient.id))

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
        elif event.event_type == Event.TYPE_FALL:
            alert_type = "FALL_DETECTED"
            confidence = event.payload.get("confidence", 0.0)
            message = f"URGENT: Patient fall detected with {confidence*100:.0f}% confidence. Immediate attention required."
        elif event.event_type == Event.TYPE_ACTIVITY:
            activity = event.payload.get("activity", "unknown")
            confidence = event.payload.get("confidence", 0.0)
            alert_type = f"{activity}_DETECTED"
            message = f"URGENT: Patient showing signs of {activity.replace('_', ' ').lower()} ({confidence*100:.0f}% confidence). Please check immediately."
        else:
            alert_type = event.event_type
            message = f"Event: {event.event_type}"

        alerts = []
        for recipient in recipients:
            alerts.append(
                Alert(
                    patient=event.patient,
                    recipient=recipient,
                    event=event,
                    alert_type=alert_type,
                    message=message,
                    status=Alert.STATUS_NEW,
                    created_at=datetime.utcnow(),
                ).save()
            )
        return alerts
