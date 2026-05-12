from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status
import asyncio

from apps.accounts.services.patient_service import PatientService
from apps.accounts.services.base import NotFoundError
from apps.monitoring.serializers import FrameIngestSerializer
from apps.monitoring.services.ai_client import track_person, AIClientError
from apps.monitoring.services.person_tracking_service import PersonTrackingService
from apps.monitoring.services.event_service import EventService
from apps.monitoring.services.alert_service import AlertService


class PersonTrackingView(APIView):
    parser_classes = (MultiPartParser, FormParser)

    """
    POST /api/person-tracking/track
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
            patient = PatientService.get_patient_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        # 2) Get face embedding and bbox from AI server
        try:
            tracking_result = track_person(frame_file, patient_id=patient_id)
        except AIClientError as e:
            return Response({"detail": str(e)}, status=status.HTTP_502_BAD_GATEWAY)

        if not tracking_result.get("face_detected", False):
            return Response({
                "detail": "No face detected in frame.",
                "tracking_result": tracking_result
            }, status=status.HTTP_200_OK)

        face_embedding = tracking_result.get("embedding")
        bbox = tracking_result.get("bbox")

        if not face_embedding:
            return Response({
                "detail": "Face detected but no embedding generated.",
                "tracking_result": tracking_result
            }, status=status.HTTP_200_OK)

        # 3) Check if this person is already being tracked
        existing_person = PersonTrackingService.find_matching_person(
            patient, face_embedding
        )

        events_created = []
        alerts_created = 0

        if existing_person:
            # Update existing person tracking
            PersonTrackingService.update_person_tracking(existing_person, bbox)
            
            # Create regular face event
            event = EventService.create_event(
                patient=patient,
                event_type="FACE",
                confidence=1.0,
                payload={
                    "tracking_id": existing_person.tracking_id,
                    "person_name": existing_person.person_name,
                    "status": existing_person.status,
                    "bbox": bbox,
                    "frame_count": existing_person.frame_count
                }
            )
            events_created.append(event)

        else:
            # Create new person tracking record
            new_person = PersonTrackingService.create_new_person(
                patient, face_embedding, bbox
            )

            # Create person enter event
            enter_event = PersonTrackingService.create_person_event(
                patient=patient,
                person_tracking=new_person,
                event_type="PERSON_ENTER",
                confidence=1.0,
                payload={
                    "tracking_id": new_person.tracking_id,
                    "status": new_person.status,
                    "bbox": bbox,
                    "first_seen": True
                }
            )
            events_created.append(enter_event)

            # Run face recognition asynchronously for new person
            try:
                # Run face recognition in background
                recognition_result = asyncio.run(
                    PersonTrackingService.process_face_recognition(new_person, frame_file)
                )

                if recognition_result.get("success"):
                    # Create face recognition event
                    face_event = PersonTrackingService.create_person_event(
                        patient=patient,
                        person_tracking=new_person,
                        event_type="FACE",
                        confidence=recognition_result.get("ai_result", {}).get("confidence", 0.0),
                        payload={
                            "tracking_id": new_person.tracking_id,
                            "person_name": new_person.person_name,
                            "status": new_person.status,
                            "recognition_result": recognition_result.get("ai_result"),
                            "bbox": bbox
                        }
                    )
                    events_created.append(face_event)

            except Exception as e:
                # Log error but don't fail the request
                print(f"Face recognition failed for {new_person.tracking_id}: {str(e)}")

        # 5) Check for alerts on all created events
        for event in events_created:
            if AlertService.should_alert_for_event(event):
                alerts = AlertService.create_alerts_for_event(event)
                alerts_created += len(alerts)

        return Response({
            "detail": "Person tracking processed.",
            "person_detected": True,
            "existing_person": existing_person is not None,
            "tracking_id": existing_person.tracking_id if existing_person else new_person.tracking_id,
            "events_created": len(events_created),
            "alerts_created": alerts_created,
            "tracking_result": tracking_result,
            "events": [
                {
                    "id": str(event.id),
                    "event_type": event.event_type,
                    "confidence": event.confidence,
                    "payload": event.payload,
                    "created_at": event.created_at,
                }
                for event in events_created
            ]
        }, status=status.HTTP_201_CREATED)


class ActivePersonsView(APIView):
    """
    GET /api/person-tracking/active?patient_id=<id>&minutes=<minutes>
    Returns all active persons for a patient
    """
    def get(self, request):
        patient_id = request.query_params.get("patient_id")
        minutes = int(request.query_params.get("minutes", 10))

        if not patient_id:
            return Response({"detail": "patient_id is required"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            patient = PatientService.get_patient_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        active_persons = PersonTrackingService.get_active_persons(patient, minutes)

        return Response({
            "patient_id": patient_id,
            "minutes": minutes,
            "active_persons": [
                {
                    "id": str(person.id),
                    "tracking_id": person.tracking_id,
                    "status": person.status,
                    "person_name": person.person_name,
                    "confidence": person.confidence,
                    "first_seen": person.first_seen,
                    "last_seen": person.last_seen,
                    "frame_count": person.frame_count,
                    "last_bbox": person.last_bbox,
                }
                for person in active_persons
            ]
        })


class CleanupPersonsView(APIView):
    """
    POST /api/person-tracking/cleanup
    Cleans up old person tracking records
    """
    def post(self, request):
        patient_id = request.data.get("patient_id")
        hours = int(request.data.get("hours", 24))

        if not patient_id:
            return Response({"detail": "patient_id is required"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            patient = PatientService.get_patient_by_id(patient_id)
        except Exception:
            return Response({"detail": "Patient not found."}, status=status.HTTP_404_NOT_FOUND)

        cleaned_count = PersonTrackingService.cleanup_old_persons(patient, hours)

        return Response({
            "detail": f"Cleaned up {cleaned_count} old person records.",
            "patient_id": patient_id,
            "hours": hours,
            "cleaned_count": cleaned_count
        })
