from datetime import datetime
from typing import Optional, List

from bson import ObjectId
from mongoengine.errors import NotUniqueError, ValidationError, DoesNotExist
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure

from apps.monitoring.models import User, PatientCaregiverLink


class UserServiceError(Exception):
    """Base exception for user service errors."""


class NotFoundError(UserServiceError):
    pass


class BadRequestError(UserServiceError):
    pass


class ConflictError(UserServiceError):
    pass


class UserService:
    # Users
    @staticmethod
    def create_user(name: str, email: str, role: str) -> User:
        name = (name or "").strip()
        email = (email or "").strip().lower()
        role = (role or "").strip().upper()

        if not name:
            raise BadRequestError("Name is required.")
        if not email:
            raise BadRequestError("Email is required.")
        if role not in (User.ROLE_PATIENT, User.ROLE_CAREGIVER):
            raise BadRequestError("Role must be PATIENT or CAREGIVER.")

        try:
            return User(
                name=name,
                email=email,
                role=role,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            ).save()
        except NotUniqueError:
            raise ConflictError("A user with this email already exists.")
        except ValidationError as e:
            raise BadRequestError(f"Invalid user data: {str(e)}")
        except (ServerSelectionTimeoutError, OperationFailure) as e:
            raise BadRequestError(f"Database error: {str(e)}")

    @staticmethod
    def get_user_by_id(user_id: str) -> User:
        try:
            oid = ObjectId(str(user_id))
            return User.objects.get(id=oid)
        except (DoesNotExist, ValidationError, Exception):
            raise NotFoundError("User not found.")

    @staticmethod
    def get_user_by_email(email: str) -> User:
        email = (email or "").strip().lower()
        if not email:
            raise BadRequestError("Email is required.")

        user = User.objects(email=email).first()
        if not user:
            raise NotFoundError("User not found.")
        return user

    @staticmethod
    def list_users(role: Optional[str] = None) -> List[User]:
        if role:
            role = role.strip().upper()
            if role not in (User.ROLE_PATIENT, User.ROLE_CAREGIVER):
                raise BadRequestError("Role filter must be PATIENT or CAREGIVER.")
            return list(User.objects(role=role).order_by("-created_at"))
        return list(User.objects.order_by("-created_at"))

    @staticmethod
    def update_user(user_id: str, name: Optional[str] = None) -> User:
        user = UserService.get_user_by_id(user_id)

        if name is not None:
            name = name.strip()
            if not name:
                raise BadRequestError("Name cannot be empty.")
            user.name = name

        user.updated_at = datetime.utcnow()
        user.save()
        return user

    # Patient <-> Caregiver Links
    @staticmethod
    def link_caregiver_to_patient(patient_id: str, caregiver_id: str) -> PatientCaregiverLink:
        patient = UserService.get_user_by_id(patient_id)
        caregiver = UserService.get_user_by_id(caregiver_id)

        if patient.role != User.ROLE_PATIENT:
            raise BadRequestError("Provided patient_id is not a PATIENT.")
        if caregiver.role != User.ROLE_CAREGIVER:
            raise BadRequestError("Provided caregiver_id is not a CAREGIVER.")

        try:
            return PatientCaregiverLink(
                patient=patient,
                caregiver=caregiver,
                created_at=datetime.utcnow(),
            ).save()
        except NotUniqueError:
            raise ConflictError("This caregiver is already linked to this patient.")
        except ValidationError as e:
            raise BadRequestError(f"Invalid link data: {str(e)}")

    @staticmethod
    def unlink_caregiver_from_patient(patient_id: str, caregiver_id: str) -> int:
        patient = UserService.get_user_by_id(patient_id)
        caregiver = UserService.get_user_by_id(caregiver_id)

        deleted = PatientCaregiverLink.objects(patient=patient, caregiver=caregiver).delete()
        if deleted == 0:
            raise NotFoundError("Link not found.")
        return deleted

    @staticmethod
    def get_caregivers_for_patient(patient_id: str) -> List[User]:
        patient = UserService.get_user_by_id(patient_id)
        if patient.role != User.ROLE_PATIENT:
            raise BadRequestError("Provided patient_id is not a PATIENT.")

        links = PatientCaregiverLink.objects(patient=patient)
        caregiver_ids = [link.caregiver.id for link in links]
        if not caregiver_ids:
            return []
        return list(User.objects(id__in=caregiver_ids))

    @staticmethod
    def get_patients_for_caregiver(caregiver_id: str) -> List[User]:
        caregiver = UserService.get_user_by_id(caregiver_id)
        if caregiver.role != User.ROLE_CAREGIVER:
            raise BadRequestError("Provided caregiver_id is not a CAREGIVER.")

        links = PatientCaregiverLink.objects(caregiver=caregiver)
        patient_ids = [link.patient.id for link in links]
        if not patient_ids:
            return []
        return list(User.objects(id__in=patient_ids))
