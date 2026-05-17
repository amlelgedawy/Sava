from datetime import datetime
from typing import List

from apps.monitoring.models import User, Patient, PatientRelativeLink
from apps.accounts.services.base import (
    get_user, get_patient, BadRequestError, ForbiddenError, NotFoundError,
)


class AdminService:

    @staticmethod
    def set_caregiver_salary(caregiver_id: str, salary_per_hour: float, admin_id: str) -> User:
        admin = get_user(admin_id)
        if admin.role != User.ROLE_ADMIN:
            raise ForbiddenError("Only admins can set caregiver salaries.")
        caregiver = get_user(caregiver_id)
        if caregiver.role != User.ROLE_CAREGIVER:
            raise BadRequestError("Target user is not a CAREGIVER.")
        caregiver.salary_per_hour = salary_per_hour
        caregiver.updated_at = datetime.utcnow()
        caregiver.save()
        return caregiver

    @staticmethod
    def list_caregivers_for_admin() -> List[User]:
        return list(User.objects(role=User.ROLE_CAREGIVER).order_by("name"))

    @staticmethod
    def delete_user(user_id: str, admin_id: str) -> None:
        admin = get_user(admin_id)
        if admin.role != User.ROLE_ADMIN:
            raise ForbiddenError("Only admins can delete users.")
        target = get_user(user_id)
        target.delete()

    @staticmethod
    def reject_caregiver(caregiver_id: str, admin_id: str) -> None:
        admin = get_user(admin_id)
        if admin.role != User.ROLE_ADMIN:
            raise ForbiddenError("Only admins can reject caregivers.")
        caregiver = get_user(caregiver_id)
        if caregiver.role != User.ROLE_CAREGIVER:
            raise BadRequestError("Target user is not a CAREGIVER.")
        caregiver.delete()

    @staticmethod
    def change_relative_role(patient_id: str, relative_id: str, new_role: str, admin_id: str) -> PatientRelativeLink:
        admin = get_user(admin_id)
        if admin.role != User.ROLE_ADMIN:
            raise ForbiddenError("Only admins can change relative roles.")
        patient = get_patient(patient_id)
        relative = get_user(relative_id)
        link = PatientRelativeLink.objects(patient=patient, relative=relative).first()
        if not link:
            raise NotFoundError("This relative is not linked to this patient.")

        new_role = new_role.strip().upper()
        if new_role not in (PatientRelativeLink.ROLE_PRIMARY, PatientRelativeLink.ROLE_SECONDARY):
            raise BadRequestError("role must be PRIMARY or SECONDARY.")

        if new_role == PatientRelativeLink.ROLE_PRIMARY:
            existing_primary = PatientRelativeLink.objects(
                patient=patient, role_type=PatientRelativeLink.ROLE_PRIMARY
            ).count()
            if link.role_type != PatientRelativeLink.ROLE_PRIMARY and existing_primary >= 2:
                raise BadRequestError("A patient can have at most 2 primary relatives.")

        link.role_type = new_role
        link.save()
        return link
