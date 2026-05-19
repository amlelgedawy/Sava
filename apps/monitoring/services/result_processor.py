"""
ResultProcessor
---------------
Interprets the JSON result returned by an AI server and decides:
  - Does this warrant an Alert?  → create Event + Alert via AlertService
  - Is it a normal activity log? → create ActivityLog

Keeps AlertService as the single authority on alert rules.
"""

from datetime import datetime

from apps.monitoring.models import Alert, ActivityLog
from apps.monitoring.models.events import Event
from apps.monitoring.services.alert_service import AlertService
from apps.monitoring.services.event_service import EventService
from apps.accounts.services.patient_service import PatientService
from apps.accounts.services.base import NotFoundError


ALERT_ACTIVITIES = {"FALL", "CHEST_PAIN"}
LOG_ACTIVITIES = {"EAT", "DRINK", "SLEEP", "WALK", "SIT", "STAND", "USE_PHONE"}
ALERT_OBJECTS = {"HIGH", "MEDIUM"}  # danger levels that trigger alerts


class ResultProcessor:

    @staticmethod
    def process(source: str, patient_id: str, result: dict) -> dict:
        """
        Entry point called by the ai-result endpoint.

        source  : "ACTIVITY_SERVER" | "FACE_SERVER"
        result  : raw JSON dict from the AI server
        Returns : summary dict (for the endpoint response)
        """
        try:
            patient = PatientService.get_patient_by_id(patient_id)
        except (NotFoundError, Exception):
            return {"error": f"Patient {patient_id} not found"}

        if source == "ACTIVITY_SERVER":
            return ResultProcessor._process_activity(patient, result)
        elif source == "FACE_SERVER":
            return ResultProcessor._process_face(patient, result)
        return {"error": f"Unknown source: {source}"}

    # ------------------------------------------------------------------
    @staticmethod
    def _process_activity(patient, result: dict) -> dict:
        summary = {"events": [], "alerts": [], "logs": []}

        activity = result.get("activity")
        confidence = float(result.get("confidence", 0.0))
        fall_alert = result.get("fall_alert", False)
        dangerous_objects = result.get("dangerous_objects", [])

        # ── Fall (persistent) ──────────────────────────────────────────
        if fall_alert:
            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_FALL,
                confidence=confidence,
                payload={"activity": "FALL", "confidence": confidence},
            )
            summary["events"].append(str(event.id))
            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                summary["alerts"] += [str(a.id) for a in alerts]

        # ── Other alert activities (CHEST_PAIN) ────────────────────────
        elif activity in ALERT_ACTIVITIES and not fall_alert:
            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_ACTIVITY,
                confidence=confidence,
                payload={"activity": activity, "confidence": confidence},
            )
            summary["events"].append(str(event.id))
            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                summary["alerts"] += [str(a.id) for a in alerts]

        # ── Normal activity log ────────────────────────────────────────
        elif activity in LOG_ACTIVITIES:
            log = ActivityLog(
                patient=patient,
                activity=activity,
                confidence=confidence,
                source="ACTIVITY_SERVER",
                payload=result,
                created_at=datetime.utcnow(),
            ).save()
            summary["logs"].append(str(log.id))

        # ── Dangerous objects ──────────────────────────────────────────
        for obj in dangerous_objects:
            danger_level = obj.get("danger_level", "LOW")
            label = obj.get("label", "unknown")
            obj_conf = float(obj.get("confidence", 0.0))

            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_OBJECT,
                confidence=obj_conf,
                payload={
                    "object_class": label,
                    "danger_level": danger_level,
                    "is_dangerous": danger_level in ALERT_OBJECTS,
                    "box": obj.get("box", {}),
                },
            )
            summary["events"].append(str(event.id))
            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                summary["alerts"] += [str(a.id) for a in alerts]

        return summary

    # ------------------------------------------------------------------
    @staticmethod
    def _process_face(patient, result: dict) -> dict:
        summary = {"events": [], "alerts": [], "logs": []}

        payload = result.get("payload", result)
        known = bool(payload.get("known", True))
        confidence = float(result.get("confidence", payload.get("confidence", 0.0)))
        person_name = payload.get("person_name")

        if not known:
            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_FACE,
                confidence=confidence,
                payload={"known": False, "person_name": person_name},
            )
            summary["events"].append(str(event.id))
            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                summary["alerts"] += [str(a.id) for a in alerts]
        else:
            log = ActivityLog(
                patient=patient,
                activity="UNKNOWN_FACE" if not known else "FACE_RECOGNIZED",
                confidence=confidence,
                source="FACE_SERVER",
                payload=payload,
                created_at=datetime.utcnow(),
            ).save()
            summary["logs"].append(str(log.id))

        return summary
