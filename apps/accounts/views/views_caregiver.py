from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.serializers import (
    CaregiverOfferSerializer, ContractActionSerializer, MedicationScheduleSerializer,
)
from apps.accounts.services.caregiver_service import CaregiverService
from apps.accounts.views.helpers import (
    serialize_user, serialize_patient, serialize_contract, handle_service_error,
)


class AvailableCaregiversView(APIView):
    """GET /api/caregivers/available"""
    def get(self, request):
        try:
            caregivers = CaregiverService.list_available_caregivers()
            return Response([serialize_user(c) for c in caregivers], status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class CaregiverOfferView(APIView):
    """POST /api/patients/<patient_id>/caregiver-offer  body: {requester_id, caregiver_id}"""
    def post(self, request, patient_id: str):
        ser = CaregiverOfferSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        requester_id = request.data.get("requester_id")
        if not requester_id:
            return Response({"detail": "requester_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            contract = CaregiverService.send_caregiver_offer(
                patient_id=patient_id,
                requester_id=requester_id,
                caregiver_id=ser.validated_data["caregiver_id"],
            )
            return Response(serialize_contract(contract), status=status.HTTP_201_CREATED)
        except Exception as e:
            return handle_service_error(e)


class ContractRespondView(APIView):
    """PATCH /api/contracts/<contract_id>/respond  body: {caregiver_id, action: ACCEPT|DECLINE}"""
    def patch(self, request, contract_id: str):
        ser = ContractActionSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        caregiver_id = request.data.get("caregiver_id")
        if not caregiver_id:
            return Response({"detail": "caregiver_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            contract = CaregiverService.respond_to_offer(
                contract_id=contract_id,
                caregiver_id=caregiver_id,
                action=ser.validated_data["action"],
            )
            return Response(serialize_contract(contract), status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class ContractEndView(APIView):
    """POST /api/contracts/<contract_id>/end  body: {user_id}"""
    def post(self, request, contract_id: str):
        user_id = request.data.get("user_id")
        if not user_id:
            return Response({"detail": "user_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            contract = CaregiverService.end_contract(contract_id, user_id)
            return Response(serialize_contract(contract), status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class CaregiverPatientsView(APIView):
    """GET /api/caregivers/<caregiver_id>/patients"""
    def get(self, request, caregiver_id: str):
        try:
            patients = CaregiverService.get_patients_for_caregiver(caregiver_id)
            return Response([serialize_patient(p) for p in patients], status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class MedicationScheduleView(APIView):
    """
    GET  /api/patients/<patient_id>/medication
    PUT  /api/patients/<patient_id>/medication  body: {user_id, entries: [...]}
    """
    def get(self, request, patient_id: str):
        try:
            schedule = CaregiverService.get_medication_schedule(patient_id)
            if not schedule:
                return Response({"entries": []}, status=status.HTTP_200_OK)
            return Response({
                "id": str(schedule.id),
                "patient_id": str(schedule.patient.id),
                "entries": [
                    {
                        "medicine_name": e.medicine_name,
                        "time_to_consume": e.time_to_consume,
                        "dosage": e.dosage,
                        "notes": e.notes,
                    }
                    for e in schedule.entries
                ],
                "created_by": str(schedule.created_by.id),
                "updated_by": str(schedule.updated_by.id) if schedule.updated_by else None,
                "created_at": schedule.created_at,
                "updated_at": schedule.updated_at,
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)

    def put(self, request, patient_id: str):
        ser = MedicationScheduleSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        user_id = request.data.get("user_id")
        if not user_id:
            return Response({"detail": "user_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            schedule = CaregiverService.upsert_medication_schedule(
                patient_id=patient_id,
                user_id=user_id,
                entries=ser.validated_data["entries"],
            )
            return Response({
                "id": str(schedule.id),
                "patient_id": str(schedule.patient.id),
                "entries": [
                    {
                        "medicine_name": e.medicine_name,
                        "time_to_consume": e.time_to_consume,
                        "dosage": e.dosage,
                        "notes": e.notes,
                    }
                    for e in schedule.entries
                ],
                "updated_at": schedule.updated_at,
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)
