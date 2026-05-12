from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.serializers import AddRelativeSerializer
from apps.accounts.services.relative_service import RelativeService
from apps.accounts.views.helpers import serialize_user, handle_service_error


class PatientRelativesView(APIView):
    """
    GET    /api/patients/<patient_id>/relatives
    POST   /api/patients/<patient_id>/relatives  body: {requester_id, relative_id, role_type}
    DELETE /api/patients/<patient_id>/relatives?requester_id=...&relative_id=...
    """
    def get(self, request, patient_id: str):
        try:
            items = RelativeService.get_relatives_for_patient(patient_id)
            return Response([
                {
                    "relative": serialize_user(item["relative"]),
                    "role_type": item["role_type"],
                }
                for item in items
            ], status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)

    def post(self, request, patient_id: str):
        ser = AddRelativeSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        requester_id = request.data.get("requester_id")
        if not requester_id:
            return Response({"detail": "requester_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            link = RelativeService.add_relative_to_patient(
                patient_id=patient_id,
                requester_id=requester_id,
                username=ser.validated_data["username"],
                role_type=ser.validated_data["role_type"],
            )
            return Response({
                "detail": "Relative added.",
                "patient_id": str(link.patient.id),
                "relative_id": str(link.relative.id),
                "role_type": link.role_type,
            }, status=status.HTTP_201_CREATED)
        except Exception as e:
            return handle_service_error(e)

    def delete(self, request, patient_id: str):
        """DELETE /api/patients/<patient_id>/relatives?requester_id=...&username=..."""
        requester_id = request.query_params.get("requester_id")
        username = request.query_params.get("username")
        if not requester_id or not username:
            return Response(
                {"detail": "requester_id and username query params are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            RelativeService.remove_relative_from_patient(patient_id, requester_id, username)
            return Response({"detail": "Secondary relative removed."}, status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)
