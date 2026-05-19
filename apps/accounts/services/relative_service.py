from datetime import datetime
from typing import List

from mongoengine.errors import NotUniqueError

from apps.monitoring.models import User, Patient, PatientRelativeLink
from apps.accounts.services.base import (
    get_user, get_patient,
    BadRequestError, ConflictError, ForbiddenError, NotFoundError,
)


class RelativeService:

    @staticmethod
    def assert_primary_relative(patient: Patient, user: User):
        if user.role == User.ROLE_ADMIN:
            return
        link = PatientRelativeLink.objects(
            patient=patient,
            relative=user,
            role_type=PatientRelativeLink.ROLE_PRIMARY,
        ).first()
        if not link:
            raise ForbiddenError("Only a primary relative can perform this action.")

    @staticmethod
    def add_relative_to_patient(patient_id: str, requester_id: str, username: str, role_type: str) -> PatientRelativeLink:
        patient = get_patient(patient_id)
        requester = get_user(requester_id)
        RelativeService.assert_primary_relative(patient, requester)

        new_relative = User.objects(username=username.strip().lower()).first()
        if not new_relative:
            raise NotFoundError(f"No user found with username '{username}'.")
        if new_relative.role != User.ROLE_RELATIVE:
            raise BadRequestError("Target user is not a RELATIVE.")

        role_type = role_type.strip().upper()

        existing_link = PatientRelativeLink.objects(patient=patient, relative=new_relative).first()
        if existing_link:
            if existing_link.role_type == role_type:
                raise ConflictError("This relative is already linked to this patient.")
            if role_type == PatientRelativeLink.ROLE_PRIMARY:
                existing_primary = PatientRelativeLink.objects(
                    patient=patient, role_type=PatientRelativeLink.ROLE_PRIMARY
                ).count()
                if existing_primary >= 2:
                    raise BadRequestError("A patient can have at most 2 primary relatives.")
            existing_link.role_type = role_type
            existing_link.save()
            return existing_link

        if role_type == PatientRelativeLink.ROLE_PRIMARY:
            existing_primary = PatientRelativeLink.objects(
                patient=patient, role_type=PatientRelativeLink.ROLE_PRIMARY
            ).count()
            if existing_primary >= 2:
                raise BadRequestError("A patient can have at most 2 primary relatives.")

        return PatientRelativeLink(
            patient=patient,
            relative=new_relative,
            role_type=role_type,
            created_at=datetime.utcnow(),
        ).save()

    @staticmethod
    def get_relatives_for_patient(patient_id: str) -> List[dict]:
        patient = get_patient(patient_id)
        links = PatientRelativeLink.objects(patient=patient)
        return [{"relative": l.relative, "role_type": l.role_type} for l in links]

    @staticmethod
    def remove_relative_from_patient(patient_id: str, requester_id: str, username: str) -> None:
        patient = get_patient(patient_id)
        requester = get_user(requester_id)
        RelativeService.assert_primary_relative(patient, requester)

        target = User.objects(username=username.strip().lower()).first()
        if not target:
            raise NotFoundError(f"No user found with username '{username}'.")
        link = PatientRelativeLink.objects(patient=patient, relative=target).first()
        if not link:
            raise NotFoundError("This relative is not linked to this patient.")
        if link.role_type == PatientRelativeLink.ROLE_PRIMARY:
            raise ForbiddenError("Cannot remove a primary relative.")
        link.delete()
