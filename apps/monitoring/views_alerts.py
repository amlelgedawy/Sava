from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from bson import ObjectId
from mongoengine.errors import DoesNotExist, ValidationError

from apps.monitoring.models import Alert
from apps.monitoring.serializers import AlertUpdateSerializer


def _ref_id(doc, field_name):
    try:
        ref = getattr(doc, field_name)
        return str(ref.id) if ref else None
    except DoesNotExist:
        return None


def _serialize_alert(a: Alert) -> dict:
    return {
        "id": str(a.id),
        "patient_id": _ref_id(a, "patient"),
        "recipient_id": _ref_id(a, "recipient"),
        "event_id": _ref_id(a, "event"),
        "alert_type": a.alert_type,
        "message": a.message,
        "status": a.status,
        "created_at": a.created_at,
    }


class AlertsListView(APIView):
    """
    GET /api/alerts?recipient_id=<id>&patient_id=<id>&status=NEW|SEEN|DISMISSED
    """
    def get(self, request):
        recipient_id = request.query_params.get("recipient_id")
        patient_id = request.query_params.get("patient_id")
        status_q = request.query_params.get("status")

        q = Alert.objects

        # Filter recipient (caregiver or relative)
        if recipient_id:
            try:
                q = q.filter(recipient=ObjectId(recipient_id))
            except Exception:
                return Response({"detail": "Invalid recipient_id."}, status=status.HTTP_400_BAD_REQUEST)

        # Optional: filter patient
        if patient_id:
            try:
                q = q.filter(patient=ObjectId(patient_id))
            except Exception:
                return Response({"detail": "Invalid patient_id."}, status=status.HTTP_400_BAD_REQUEST)

        # Optional: filter status
        if status_q:
            status_q = status_q.strip().upper()
            if status_q not in ("NEW", "SEEN", "DISMISSED"):
                return Response({"detail": "status must be NEW, SEEN, or DISMISSED."}, status=status.HTTP_400_BAD_REQUEST)
            q = q.filter(status=status_q)

        alerts = list(q.order_by("-created_at").limit(200))
        return Response([_serialize_alert(a) for a in alerts], status=status.HTTP_200_OK)


class AlertDetailView(APIView):
    """
    GET   /api/alerts/<alert_id>
    PATCH /api/alerts/<alert_id>   body: {"status": "SEEN"|"NEW"}
    """
    def get(self, request, alert_id: str):
        try:
            a = Alert.objects.get(id=ObjectId(alert_id))
            return Response(_serialize_alert(a), status=status.HTTP_200_OK)
        except Exception:
            return Response({"detail": "Alert not found."}, status=status.HTTP_404_NOT_FOUND)

    def patch(self, request, alert_id: str):
        ser = AlertUpdateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        try:
            a = Alert.objects.get(id=ObjectId(alert_id))
        except Exception:
            return Response({"detail": "Alert not found."}, status=status.HTTP_404_NOT_FOUND)

        a.status = ser.validated_data["status"]
        a.save()

        return Response(_serialize_alert(a), status=status.HTTP_200_OK)
