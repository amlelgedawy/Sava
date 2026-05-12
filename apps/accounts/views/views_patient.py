from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.serializers import PatientCreateSerializer, PatientUpdateSerializer
from apps.accounts.services.patient_service import PatientService
from apps.accounts.views.helpers import serialize_patient, handle_service_error


class PatientListCreateView(APIView):
    """
    GET  /api/patients?relative_id=...
    POST /api/patients   body: {relative_id, name, date_of_birth, gender, current_medication}
    """
    def get(self, request):
        relative_id = request.query_params.get("relative_id")
        if not relative_id:
            return Response({"detail": "relative_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            items = PatientService.get_patients_for_relative(relative_id)
            result = []
            for item in items:
                p = serialize_patient(item["patient"])
                p["role_type"] = item["role_type"]
                result.append(p)
            return Response(result, status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)

    def post(self, request):
        ser = PatientCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        relative_id = request.data.get("relative_id")
        if not relative_id:
            return Response({"detail": "relative_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            patient = PatientService.create_patient(
                relative_id=relative_id, **ser.validated_data
            )
            return Response(serialize_patient(patient), status=status.HTTP_201_CREATED)
        except Exception as e:
            return handle_service_error(e)


class PatientDetailView(APIView):
    """
    GET   /api/patients/<patient_id>
    PATCH /api/patients/<patient_id>   body: {user_id, ...fields}
    """
    def get(self, request, patient_id: str):
        try:
            patient = PatientService.get_patient_by_id(patient_id)
            return Response(serialize_patient(patient), status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)

    def patch(self, request, patient_id: str):
        ser = PatientUpdateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        user_id = request.data.get("user_id")
        if not user_id:
            return Response({"detail": "user_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            patient = PatientService.update_patient(patient_id, user_id, **ser.validated_data)
            return Response(serialize_patient(patient), status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)
