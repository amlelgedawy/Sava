from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.serializers import (
    LoginSerializer, RelativeSignUpSerializer, CaregiverSignUpSerializer,
)
from apps.accounts.services.auth_service import AuthService
from apps.accounts.views.helpers import save_cv, serialize_user, handle_service_error


class LoginView(APIView):
    """POST /api/auth/login"""
    def post(self, request):
        ser = LoginSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            user = AuthService.authenticate(**ser.validated_data)
            return Response(serialize_user(user), status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class RelativeSignUpView(APIView):
    """POST /api/auth/signup/relative"""
    def post(self, request):
        ser = RelativeSignUpSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            user = AuthService.register_relative(
                name=ser.validated_data["name"],
                username=ser.validated_data["username"],
                email=ser.validated_data["email"],
                password=ser.validated_data["password"],
            )
            return Response(serialize_user(user), status=status.HTTP_201_CREATED)
        except Exception as e:
            return handle_service_error(e)


class CaregiverSignUpView(APIView):
    """POST /api/auth/signup/caregiver  (multipart/form-data for CV upload)"""
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request):
        ser = CaregiverSignUpSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        cv_path = None
        cv_file = ser.validated_data.get("cv")
        if cv_file:
            cv_path = save_cv(cv_file, ser.validated_data["email"])

        try:
            user = AuthService.register_caregiver(
                name=ser.validated_data["name"],
                username=ser.validated_data["username"],
                email=ser.validated_data["email"],
                password=ser.validated_data["password"],
                age=ser.validated_data["age"],
                national_id=ser.validated_data["national_id"],
                cv_path=cv_path,
            )
            return Response(serialize_user(user), status=status.HTTP_201_CREATED)
        except Exception as e:
            return handle_service_error(e)


class UserDetailView(APIView):
    """GET /api/users/<user_id>"""
    def get(self, request, user_id: str):
        try:
            user = AuthService.get_user_by_id(user_id)
            return Response(serialize_user(user), status=status.HTTP_200_OK)
        except Exception as e:
            return handle_service_error(e)


class UserSearchView(APIView):
    """GET /api/users/search?q=...&role=RELATIVE"""
    def get(self, request):
        query = request.query_params.get("q", "").strip()
        if not query:
            return Response({"detail": "q query param is required."}, status=status.HTTP_400_BAD_REQUEST)
        role = request.query_params.get("role")
        users = AuthService.search_users(query, role=role)
        return Response([serialize_user(u) for u in users], status=status.HTTP_200_OK)
