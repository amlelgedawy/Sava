from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.services.patient_service import PatientService
from apps.monitoring.models import Event
from apps.monitoring.services.event_service import EventService
from apps.monitoring.services.alert_service import AlertService


class ObjectDetectionEventView(APIView):
    """
    POST /api/object-detection/event
    Called by the camera pipeline when a dangerous object is detected.

    JSON body:
      - patient_id: str (required)
      - label: str (required) — detected object class name (e.g. "knife", "scissors")
      - confidence: float (required) — 0.0 to 1.0
      - danger_level: str (optional) — "HIGH", "MEDIUM", "LOW"
      - box: dict (optional) — normalized bounding box {x1, y1, x2, y2}
    """

    def post(self, request):
        patient_id = request.data.get("patient_id")
        label = request.data.get("label", "").lower()
        confidence = float(request.data.get("confidence", 0.0))
        danger_level = request.data.get("danger_level", "LOW").upper()
        box = request.data.get("box", {})

        if not patient_id or not label:
            return Response(
                {"detail": "patient_id and label are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            patient = PatientService.get_patient_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        event = EventService.create_event(
            patient=patient,
            event_type=Event.TYPE_OBJECT,
            confidence=confidence,
            payload={
                "object_class": label,
                "danger_level": danger_level,
                "is_dangerous": True,
                "box": box,
                "source": "object_detection",
            },
        )

        alerts_created = 0
        if AlertService.should_alert_for_event(event):
            alerts = AlertService.create_alerts_for_event(event)
            alerts_created = len(alerts)

        return Response(
            {
                "detail": "Object detection event processed.",
                "patient_id": str(patient.id),
                "object_class": label,
                "danger_level": danger_level,
                "events_created": 1,
                "alerts_created": alerts_created,
                "event": {
                    "id": str(event.id),
                    "event_type": event.event_type,
                    "confidence": event.confidence,
                    "payload": event.payload,
                    "created_at": event.created_at,
                },
            },
            status=status.HTTP_201_CREATED,
        )


class ObjectDetectionFrameView(APIView):
    """
    POST /api/object-detection/detect
    Accepts a frame + patient_id, forwards to the detection server, and creates
    events/alerts for any dangerous objects found.

    multipart/form-data:
      - patient_id: str (required)
      - frame: image file (required)
    """
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request):
        patient_id = request.data.get("patient_id")
        frame_file = request.FILES.get("frame")

        if not patient_id or not frame_file:
            return Response(
                {"detail": "patient_id and frame are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            patient = PatientService.get_patient_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        from apps.monitoring.services.ai_client import detect_objects, AIClientError

        try:
            result = detect_objects(frame_file)
        except AIClientError as e:
            return Response({"detail": str(e)}, status=status.HTTP_502_BAD_GATEWAY)

        detections = result.get("detections", [])
        events_created = []
        alerts_created = 0

        for det in detections:
            if not det.get("is_dangerous", False):
                continue

            event = EventService.create_event(
                patient=patient,
                event_type=Event.TYPE_OBJECT,
                confidence=float(det.get("confidence", 0.0)),
                payload={
                    "object_class": det.get("label", "unknown"),
                    "danger_level": det.get("danger_level", "LOW"),
                    "is_dangerous": True,
                    "box": det.get("box", {}),
                    "source": "object_detection",
                },
            )
            events_created.append(event)

            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                alerts_created += len(alerts)

        return Response(
            {
                "detail": "Frame processed for object detection.",
                "patient_id": str(patient.id),
                "detections_count": len(detections),
                "events_created": len(events_created),
                "alerts_created": alerts_created,
                "detections": detections,
            },
            status=status.HTTP_201_CREATED,
        )
