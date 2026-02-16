from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.services.user_service import UserService, NotFoundError
from apps.monitoring.serializers import FrameIngestSerializer
from apps.monitoring.services.ai_client import analyze_face, AIClientError
from apps.monitoring.services.event_service import EventService
from apps.monitoring.services.alert_service import AlertService


class FrameIngestView(APIView):
    parser_classes = (MultiPartParser, FormParser)

    """
    POST /api/frames/ingest
    multipart/form-data:
      - patient_id: string
      - frame: image file
      - (optional) camera_id, timestamp
    """
    def post(self, request):
        ser = FrameIngestSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        patient_id = ser.validated_data["patient_id"]
        frame_file = ser.validated_data["frame"]

        # 1) Validate patient exists
        try:
            patient = UserService.get_user_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        # 2) Send to AI server
        try:
            ai_result = analyze_face(frame_file, patient_id=patient_id)
        except AIClientError as e:
            return Response({"detail": str(e)}, status=status.HTTP_502_BAD_GATEWAY)

        # 3) Normalize AI response
        event_type = (ai_result.get("event_type") or "FACE").upper()
        confidence = ai_result.get("confidence", 0.0)
        payload = ai_result.get("payload", {})

        # 4) Save event
        event = EventService.create_event(
            patient=patient,
            event_type=event_type,
            confidence=confidence,
            payload=payload,
        )

        # 5) Alert logic
        alerts_created = 0
        if AlertService.should_alert_for_event(event):
            alerts = AlertService.create_alerts_for_event(event)
            alerts_created = len(alerts)

        return Response(
            {
                "detail": "Frame processed.",
                "event": {
                    "id": str(event.id),
                    "patient_id": str(patient.id),
                    "event_type": event.event_type,
                    "confidence": event.confidence,
                    "payload": event.payload,
                    "created_at": event.created_at,
                },
                "alerts_created": alerts_created,
            },
            status=status.HTTP_201_CREATED,
        )

