from datetime import datetime
from typing import List

from mongoengine.errors import ValidationError

from apps.monitoring.models import User, Patient, PatientRelativeLink
from apps.accounts.services.base import (
    get_user, get_patient, BadRequestError, ForbiddenError,
)


class PatientService:

    @staticmethod
    def create_patient(relative_id: str, name: str, date_of_birth, gender: str, current_medication: str = None, face_video_path: str = None) -> Patient:
        relative = get_user(relative_id)
        if relative.role != User.ROLE_RELATIVE:
            raise ForbiddenError("Only relatives can create patient profiles.")

        try:
            patient = Patient(
                name=name.strip(),
                date_of_birth=datetime.combine(date_of_birth, datetime.min.time()) if not isinstance(date_of_birth, datetime) else date_of_birth,
                gender=gender.strip().upper(),
                current_medication=current_medication,
                face_video_path=face_video_path,
                created_by=relative,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            ).save()
        except ValidationError as e:
            raise BadRequestError(f"Invalid patient data: {e}")

        PatientRelativeLink(
            patient=patient,
            relative=relative,
            role_type=PatientRelativeLink.ROLE_PRIMARY,
            created_at=datetime.utcnow(),
        ).save()

        return patient

    @staticmethod
    def get_patient_by_id(patient_id: str) -> Patient:
        return get_patient(patient_id)

    @staticmethod
    def update_patient(patient_id: str, user_id: str, **fields) -> Patient:
        from apps.accounts.services.relative_service import RelativeService

        patient = get_patient(patient_id)
        user = get_user(user_id)
        RelativeService.assert_primary_relative(patient, user)

        for key in ("name", "date_of_birth", "gender", "current_medication"):
            if key in fields and fields[key] is not None:
                val = fields[key]
                if key == "date_of_birth" and not isinstance(val, datetime):
                    val = datetime.combine(val, datetime.min.time())
                setattr(patient, key, val)
        patient.updated_at = datetime.utcnow()
        patient.save()
        return patient

    @staticmethod
    def get_patients_for_relative(relative_id: str) -> List[dict]:
        relative = get_user(relative_id)
        links = PatientRelativeLink.objects(relative=relative)
        result = []
        for link in links:
            result.append({
                "patient": link.patient,
                "role_type": link.role_type,
            })
        return result
