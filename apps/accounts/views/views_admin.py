from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.serializers import SetSalarySerializer
from apps.accounts.services.auth_service import AuthService
from apps.accounts.services.admin_service import AdminService
from apps.accounts.views.helpers import serialize_user, serialize_contract, handle_service_error


class AdminCaregiversView(APIView):
    """GET /api/admin/caregivers"""
    def get(self, request):
        try:
            caregivers = AdminService.list_caregivers_for_admin()
            return Response([serialize_user(c) for c in caregivers], status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class AdminSetSalaryView(APIView):
    """PATCH /api/admin/caregivers/<caregiver_id>/salary  body: {admin_id, salary_per_hour}"""
    def patch(self, request, caregiver_id: str):
        ser = SetSalarySerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        admin_id = request.data.get("admin_id")
        if not admin_id:
            return Response({"detail": "admin_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            caregiver = AdminService.set_caregiver_salary(
                caregiver_id=caregiver_id,
                salary_per_hour=ser.validated_data["salary_per_hour"],
                admin_id=admin_id,
            )
            return Response(serialize_user(caregiver), status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class AdminDeleteUserView(APIView):
    """DELETE /api/admin/users/<user_id>  body: {admin_id}"""
    def delete(self, request, user_id: str):
        admin_id = request.data.get("admin_id")
        if not admin_id:
            return Response({"detail": "admin_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            AdminService.delete_user(user_id, admin_id)
            return Response({"detail": "User deleted."}, status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class AdminUsersListView(APIView):
    """GET /api/admin/users?role=CAREGIVER|RELATIVE|ADMIN"""
    def get(self, request):
        role = request.query_params.get("role")
        try:
            users = AuthService.list_users(role=role)
            return Response([serialize_user(u) for u in users], status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class AdminRejectCaregiverView(APIView):
    """DELETE /api/admin/caregivers/<caregiver_id>/reject  body: {admin_id}"""
    def delete(self, request, caregiver_id: str):
        admin_id = request.data.get("admin_id")
        if not admin_id:
            return Response({"detail": "admin_id is required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            AdminService.reject_caregiver(caregiver_id, admin_id)
            return Response({"detail": "Caregiver application rejected."}, status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class AdminChangeRelativeRoleView(APIView):
    """PATCH /api/admin/patients/<patient_id>/relatives/<relative_id>/role  body: {admin_id, role}"""
    def patch(self, request, patient_id: str, relative_id: str):
        admin_id = request.data.get("admin_id")
        new_role = request.data.get("role")
        if not admin_id or not new_role:
            return Response({"detail": "admin_id and role are required."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            link = AdminService.change_relative_role(patient_id, relative_id, new_role, admin_id)
            return Response({
                "detail": "Relative role updated.",
                "patient_id": str(link.patient.id),
                "relative_id": str(link.relative.id),
                "role_type": link.role_type,
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)
