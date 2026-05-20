
#Stream views — Layer 2 (Ingestion / Transport)


import json
from datetime import datetime

from django.conf import settings
from django.http import StreamingHttpResponse, JsonResponse
from django.views import View
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from rest_framework.response import Response
from rest_framework import status

from apps.monitoring.services.stream_manager import StreamManager
from apps.monitoring.services.ai_dispatcher import dispatch
from apps.monitoring.services.result_processor import ResultProcessor
from apps.monitoring.models import ActivityLog, SensorReading
from apps.accounts.services.patient_service import PatientService


# POST /api/stream/push-frame

class PushFrameView(APIView):
    """
    Raspberry Pi pushes frames here.
    """
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request):
        # Authenticate Raspberry Pi
        key = request.headers.get("X-Api-Key", "")
        if key != settings.PI_API_KEY:
            return Response({"detail": "Unauthorized."}, status=status.HTTP_401_UNAUTHORIZED)

        patient_id = request.data.get("patient_id", "").strip()
        if not patient_id:
            return Response({"detail": "patient_id required."}, status=status.HTTP_400_BAD_REQUEST)

        frame_file = request.FILES.get("frame")
        if not frame_file:
            return Response({"detail": "frame required."}, status=status.HTTP_400_BAD_REQUEST)

        jpeg_bytes = frame_file.read()

        # Buffer frame for MJPEG stream
        StreamManager.push_frame(patient_id, jpeg_bytes)

        # Store sensor readings if provided
        _store_sensor_reading(patient_id, request.data)

        # Dispatch to AI servers asynchronously
        django_port = request.META.get("SERVER_PORT", 8000)
        dispatch(patient_id, jpeg_bytes, django_port=int(django_port))

        return Response({"detail": "accepted"}, status=status.HTTP_202_ACCEPTED)


# GET /api/stream/live/<patient_id>

@method_decorator(csrf_exempt, name="dispatch")
class LiveStreamView(View):
    """
    MJPEG stream consumed by Flutter's Image.network().
    No DRF — uses raw Django streaming response.
    """

    def get(self, request, patient_id: str):
        resp = StreamingHttpResponse(
            StreamManager.mjpeg_generator(patient_id, fps=10),
            content_type="multipart/x-mixed-replace; boundary=frame",
        )
        resp["Access-Control-Allow-Origin"] = "*"
        return resp


# GET /api/stream/snapshot/<patient_id>

@method_decorator(csrf_exempt, name="dispatch")
class SnapshotView(View):
    """
    Returns the latest single JPEG frame for a patient.
    Flutter polls this at ~10fps to render a pseudo-live feed (Image.network
    cannot decode multipart/x-mixed-replace MJPEG streams).
    """

    def get(self, request, patient_id: str):
        from django.http import HttpResponse, HttpResponseNotFound
        frame = StreamManager.get_latest_frame(patient_id)
        if not frame:
            return HttpResponseNotFound("No frame available")
        resp = HttpResponse(frame, content_type="image/jpeg")
        resp["Cache-Control"] = "no-store"
        # CORS headers for Flutter Web
        resp["Access-Control-Allow-Origin"] = "*"
        resp["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        resp["Access-Control-Allow-Headers"] = "*"
        return resp

    def options(self, request, patient_id: str):
        """Handle CORS preflight requests."""
        from django.http import HttpResponse
        resp = HttpResponse()
        resp["Access-Control-Allow-Origin"] = "*"
        resp["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        resp["Access-Control-Allow-Headers"] = "*"
        return resp


# POST /api/stream/ai-result

class AIResultView(APIView):
    """
    Receives AI inference results from AIDispatcher callbacks.
    Routes to ResultProcessor which saves Events / ActivityLogs / Alerts.
    """
    parser_classes = (JSONParser,)

    def post(self, request):
        source = request.data.get("source")
        patient_id = request.data.get("patient_id")
        result = request.data.get("result", {})

        if not source or not patient_id or not isinstance(result, dict):
            return Response({"detail": "source, patient_id and result required."}, status=status.HTTP_400_BAD_REQUEST)

        # Cache the latest result so Flutter can poll for live AR overlay
        StreamManager.set_detection(patient_id, source, result)

        summary = ResultProcessor.process(source, patient_id, result)

        if "error" in summary:
            return Response(summary, status=status.HTTP_404_NOT_FOUND)

        return Response(summary, status=status.HTTP_200_OK)


# GET /api/stream/latest-detections/<patient_id>

class LatestDetectionsView(APIView):
    """
    Returns the latest cached AI results for a patient, used by Flutter
    to render AR overlay boxes on top of the live MJPEG stream.
    """

    def get(self, request, patient_id: str):
        detections = StreamManager.get_detections(patient_id)
        return Response(detections, status=status.HTTP_200_OK)


# GET /api/stream/activity-log/<patient_id>

class ActivityLogView(APIView):
    
    """Flutter polls this to show the patient's recent activity timeline.
    Returns the 50 most recent ActivityLog entries for the patient.
    """

    def get(self, request, patient_id: str):
        try:
            patient = PatientService.get_patient_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        limit = min(int(request.query_params.get("limit", 50)), 100)

        logs = (
            ActivityLog.objects(patient=patient)
            .order_by("-created_at")
            .limit(limit)
        )

        data = [
            {
                "id": str(log.id),
                "activity": log.activity,
                "confidence": log.confidence,
                "source": log.source,
                "payload": log.payload,
                "created_at": log.created_at.isoformat(),
            }
            for log in logs
        ]

        return Response({"count": len(data), "results": data}, status=status.HTTP_200_OK)


def _store_sensor_reading(patient_id: str, data) -> None:
    """
    Persist HRV and accelerometer values sent alongside a frame.
    Silently skips if no sensor fields are present or patient lookup fails.
    """
    hrv = data.get("hrv")
    accel_x = data.get("accel_x")
    accel_y = data.get("accel_y")
    accel_z = data.get("accel_z")

    if not any(v is not None for v in [hrv, accel_x, accel_y, accel_z]):
        return

    try:
        patient = PatientService.get_patient_by_id(patient_id)
        SensorReading(
            patient=patient,
            hrv=float(hrv) if hrv is not None else None,
            accel_x=float(accel_x) if accel_x is not None else None,
            accel_y=float(accel_y) if accel_y is not None else None,
            accel_z=float(accel_z) if accel_z is not None else None,
            created_at=datetime.utcnow(),
        ).save()
    except Exception as e:
        print(f"[PushFrame] Sensor storage error: {e}")
