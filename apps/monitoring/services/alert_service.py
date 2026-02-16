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
        # Current rule: unknown face only
        if event.event_type != Event.TYPE_FACE:
            return False

        known = bool(event.payload.get("known", True))
        if known:
            return False

        if event.confidence < settings.FACE_UNKNOWN_THRESHOLD:
            return False

        if not AlertService._cooldown_passed(event.patient, event.event_type):
            return False

        caregivers = UserService.get_caregivers_for_patient(str(event.patient.id))
        if not caregivers:
            return False

        return True

    @staticmethod
    def create_alerts_for_event(event: Event) -> list[Alert]:
        caregivers = UserService.get_caregivers_for_patient(str(event.patient.id))

        alerts = []
        for cg in caregivers:
            alerts.append(
                Alert(
                    patient=event.patient,
                    caregiver=cg,
                    event=event,
                    alert_type=event.event_type,
                    message="Unknown person detected.",
                    status=Alert.STATUS_NEW,
                    created_at=datetime.utcnow(),
                ).save()
            )
        return alerts
