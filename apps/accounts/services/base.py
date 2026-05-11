from bson import ObjectId
from apps.monitoring.models import User, Patient


# Exceptions

class UserServiceError(Exception):
    pass


class NotFoundError(UserServiceError):
    pass


class BadRequestError(UserServiceError):
    pass


class ConflictError(UserServiceError):
    pass


class ForbiddenError(UserServiceError):
    pass


# Object ID resolvers

def get_user(user_id: str) -> User:
    try:
        return User.objects.get(id=ObjectId(str(user_id)))
    except Exception:
        raise NotFoundError("User not found.")


def get_patient(patient_id: str) -> Patient:
    try:
        return Patient.objects.get(id=ObjectId(str(patient_id)))
    except Exception:
        raise NotFoundError("Patient not found.")
