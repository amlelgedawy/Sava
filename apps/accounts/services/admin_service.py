from datetime import datetime
from typing import List

from apps.monitoring.models import User
from apps.accounts.services.base import (
    get_user, BadRequestError, ForbiddenError,
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
