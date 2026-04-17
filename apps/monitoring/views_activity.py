from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.services.user_service import UserService
from apps.monitoring.models import Event, User
from apps.monitoring.services.event_service import EventService
from apps.monitoring.services.alert_service import AlertService


class ActivityEventView(APIView):
    """
    POST /api/activity-recognition/event
    Called by the camera activity recognition system when a notable activity is detected.

    JSON body:
      - patient_id: str (required)
      - activity: str (required) — one of CLASS_NAMES (e.g. "FALL", "WALK", "CHEST_PAIN")
      - confidence: float (required) — 0.0 to 1.0
    """

    # Activities that generate FALL events (highest priority)
    FALL_ACTIVITIES = {"FALL"}

    # Activities that generate ACTIVITY events with alerts
    DANGEROUS_ACTIVITIES = {"CHEST_PAIN"}

    # Activities that are normal (logged but no alert)
    NORMAL_ACTIVITIES = {"EAT", "DRINK", "SLEEP", "WALK", "SIT", "STAND", "USE_PHONE"}

    def post(self, request):
        patient_id = request.data.get("patient_id")
        activity = request.data.get("activity", "").upper()
        confidence = request.data.get("confidence", 0.0)

        if not patient_id or not activity:
            return Response(
                {"detail": "patient_id and activity are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            patient = UserService.get_user_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        events_created = []
        alerts_created = 0

        # --- Handle FALL ---
        if activity in self.FALL_ACTIVITIES:
            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_FALL,
                confidence=float(confidence),
                payload={
                    "activity": activity,
                    "confidence": float(confidence),
                    "source": "activity_recognition",
                },
            )
            events_created.append(event)
            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                alerts_created += len(alerts)

        # --- Handle CHEST_PAIN and other dangerous activities ---
        elif activity in self.DANGEROUS_ACTIVITIES:
            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_ACTIVITY,
                confidence=float(confidence),
                payload={
                    "activity": activity,
                    "confidence": float(confidence),
                    "source": "activity_recognition",
                },
            )
            events_created.append(event)
            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                alerts_created += len(alerts)

        # --- Handle normal activities (log only) ---
        elif activity in self.NORMAL_ACTIVITIES:
            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_ACTIVITY,
                confidence=float(confidence),
                payload={
                    "activity": activity,
                    "confidence": float(confidence),
                    "source": "activity_recognition",
                },
            )
            events_created.append(event)

        return Response(
            {
                "detail": "Activity event processed.",
                "patient_id": str(patient.id),
                "activity": activity,
                "events_created": len(events_created),
                "alerts_created": alerts_created,
                "events": [
                    {
                        "id": str(e.id),
                        "event_type": e.event_type,
                        "confidence": e.confidence,
                        "payload": e.payload,
                        "created_at": e.created_at,
                    }
                    for e in events_created
                ],
            },
            status=status.HTTP_201_CREATED,
        )


class ActivityHistoryView(APIView):
    """
    GET /api/activity-recognition/history?patient_id=...&minutes=60
    Returns recent activity events for a patient.
    """

    def get(self, request):
        patient_id = request.query_params.get("patient_id")
        minutes = int(request.query_params.get("minutes", 60))

        if not patient_id:
            return Response(
                {"detail": "patient_id is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            patient = UserService.get_user_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        from datetime import datetime, timedelta

        cutoff = datetime.utcnow() - timedelta(minutes=minutes)
        activity_types = [Event.TYPE_ACTIVITY, Event.TYPE_FALL]
        events = Event.objects(
            patient=patient,
            event_type__in=activity_types,
            created_at__gte=cutoff,
        ).order_by("-created_at")

        return Response(
            {
                "patient_id": str(patient.id),
                "minutes": minutes,
                "total_events": events.count(),
                "events": [
                    {
                        "id": str(e.id),
                        "event_type": e.event_type,
                        "confidence": e.confidence,
                        "payload": e.payload,
                        "created_at": e.created_at,
                    }
                    for e in events
                ],
            }
        )


class PatientLookupView(APIView):
    """
    GET /api/activity-recognition/patient-lookup?name=<person_name>
    Called by the camera system to resolve a face recognition name to a patient_id.
    Searches for a PATIENT user whose name matches (case-insensitive).
    """

    def get(self, request):
        name = request.query_params.get("name", "").strip()

        if not name:
            return Response(
                {"detail": "name query parameter is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Case-insensitive search for patients matching this name
        patients = User.objects(role=User.ROLE_PATIENT, name__icontains=name)

        if not patients:
            return Response(
                {"found": False, "patient_id": None, "name": name},
                status=status.HTTP_200_OK,
            )

        # Return the first matching patient
        patient = patients.first()
        return Response(
            {
                "found": True,
                "patient_id": str(patient.id),
                "name": patient.name,
                "role": patient.role,
            },
            status=status.HTTP_200_OK,
        )
