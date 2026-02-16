from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.serializers import (
    UserCreateSerializer,
    UserUpdateSerializer,
    UserResponseSerializer,
)
from apps.accounts.services.user_service import (
    UserService,
    BadRequestError,
    NotFoundError,
    ConflictError,
)


def _serialize_user(user):
    data = {
        "id": str(user.id),
        "name": user.name,
        "email": user.email,
        "role": user.role,
        "created_at": user.created_at,
        "updated_at": user.updated_at,
    }
    return UserResponseSerializer(data).data


def _handle_service_error(e: Exception):
    if isinstance(e, BadRequestError):
        return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)
    if isinstance(e, NotFoundError):
        return Response({"detail": str(e)}, status=status.HTTP_404_NOT_FOUND)
    if isinstance(e, ConflictError):
        return Response({"detail": str(e)}, status=status.HTTP_409_CONFLICT)
    return Response({"detail": "Internal server error."}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class UsersListCreateView(APIView):
    """
    GET  /api/users?role=PATIENT|CAREGIVER
    POST /api/users
    """
    def get(self, request):
        role = request.query_params.get("role")
        try:
            users = UserService.list_users(role=role)
            return Response([_serialize_user(u) for u in users], status=status.HTTP_200_OK)
        except Exception as e:
            return _handle_service_error(e)

    def post(self, request):
        ser = UserCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            user = UserService.create_user(**ser.validated_data)
            return Response(_serialize_user(user), status=status.HTTP_201_CREATED)
        except Exception as e:
            return _handle_service_error(e)


class UserDetailView(APIView):
    """
    GET   /api/users/<user_id>
    PATCH /api/users/<user_id>
    """
    def get(self, request, user_id: str):
        try:
            user = UserService.get_user_by_id(user_id)
            return Response(_serialize_user(user), status=status.HTTP_200_OK)
        except Exception as e:
            return _handle_service_error(e)

    def patch(self, request, user_id: str):
        ser = UserUpdateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            user = UserService.update_user(user_id, **ser.validated_data)
            return Response(_serialize_user(user), status=status.HTTP_200_OK)
        except Exception as e:
            return _handle_service_error(e)


class LinkCaregiverToPatientView(APIView):
    """
    POST   /api/patients/<patient_id>/caregivers/<caregiver_id>
    DELETE /api/patients/<patient_id>/caregivers/<caregiver_id>
    """
    def post(self, request, patient_id: str, caregiver_id: str):
        try:
            link = UserService.link_caregiver_to_patient(patient_id, caregiver_id)
            return Response(
                {
                    "detail": "Linked successfully.",
                    "patient_id": str(link.patient.id),
                    "caregiver_id": str(link.caregiver.id),
                    "created_at": link.created_at,
                },
                status=status.HTTP_201_CREATED,
            )
        except Exception as e:
            return _handle_service_error(e)

    def delete(self, request, patient_id: str, caregiver_id: str):
        try:
            UserService.unlink_caregiver_from_patient(patient_id, caregiver_id)
            return Response({"detail": "Unlinked successfully."}, status=status.HTTP_200_OK)
        except Exception as e:
            return _handle_service_error(e)


class PatientCaregiversView(APIView):
    """
    GET /api/patients/<patient_id>/caregivers
    """
    def get(self, request, patient_id: str):
        try:
            caregivers = UserService.get_caregivers_for_patient(patient_id)
            return Response([_serialize_user(u) for u in caregivers], status=status.HTTP_200_OK)
        except Exception as e:
            return _handle_service_error(e)


class CaregiverPatientsView(APIView):
    """
    GET /api/caregivers/<caregiver_id>/patients
    """
    def get(self, request, caregiver_id: str):
        try:
            patients = UserService.get_patients_for_caregiver(caregiver_id)
            return Response([_serialize_user(u) for u in patients], status=status.HTTP_200_OK)
        except Exception as e:
            return _handle_service_error(e)
