import os
import uuid
import traceback

from django.conf import settings as django_settings
from rest_framework.response import Response
from rest_framework import status

from apps.accounts.serializers import UserResponseSerializer, PatientResponseSerializer
from apps.accounts.services.base import (
    BadRequestError, NotFoundError, ConflictError, ForbiddenError,
)


def save_cv(cv_file, email: str) -> str:
    """Save an uploaded CV PDF and return its relative path under MEDIA_ROOT."""
    cv_dir = os.path.join(django_settings.MEDIA_ROOT, "cvs")
    os.makedirs(cv_dir, exist_ok=True)
    safe_email = email.replace("@", "_at_").replace(".", "_")
    filename = f"{safe_email}_{uuid.uuid4().hex[:8]}.pdf"
    dest = os.path.join(cv_dir, filename)
    with open(dest, "wb") as f:
        for chunk in cv_file.chunks():
            f.write(chunk)
    return os.path.join("cvs", filename)


def serialize_user(user):
    data = {
        "id": str(user.id),
        "name": user.name,
        "username": user.username,
        "email": user.email,
        "role": user.role,
        "face_video_path": user.face_video_path,
        "age": user.age,
        "national_id": user.national_id,
        "cv_path": user.cv_path,
        "salary_per_hour": user.salary_per_hour,
        "created_at": user.created_at,
        "updated_at": user.updated_at,
    }
    return UserResponseSerializer(data).data


def serialize_patient(patient):
    return PatientResponseSerializer({
        "id": str(patient.id),
        "name": patient.name,
        "date_of_birth": patient.date_of_birth,
        "age": patient.age,
        "gender": patient.gender,
        "current_medication": patient.current_medication,
        "face_video_path": patient.face_video_path,
        "created_by": str(patient.created_by.id),
        "created_at": patient.created_at,
        "updated_at": patient.updated_at,
    }).data


def serialize_contract(c):
    return {
        "id": str(c.id),
        "patient_id": str(c.patient.id),
        "caregiver_id": str(c.caregiver.id),
        "offered_by": str(c.offered_by.id),
        "status": c.status,
        "created_at": c.created_at,
        "accepted_at": c.accepted_at,
        "ended_at": c.ended_at,
    }


def handle_service_error(e: Exception):
    if isinstance(e, BadRequestError):
        return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)
    if isinstance(e, NotFoundError):
        return Response({"detail": str(e)}, status=status.HTTP_404_NOT_FOUND)
    if isinstance(e, ConflictError):
        return Response({"detail": str(e)}, status=status.HTTP_409_CONFLICT)
    if isinstance(e, ForbiddenError):
        return Response({"detail": str(e)}, status=status.HTTP_403_FORBIDDEN)
    traceback.print_exc()
    return Response({"detail": "Internal server error."}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
