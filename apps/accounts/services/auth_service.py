from datetime import datetime
from typing import Optional, List

from mongoengine.errors import NotUniqueError, ValidationError

from apps.monitoring.models import User
from apps.accounts.services.base import (
    get_user, BadRequestError, ConflictError,
)


class AuthService:

    @staticmethod
    def register_relative(name: str, username: str, email: str, password: str, face_video_path: str = None) -> User:
        name = (name or "").strip()
        username = (username or "").strip().lower()
        email = (email or "").strip().lower()
        if not name:
            raise BadRequestError("Name is required.")
        if not username:
            raise BadRequestError("Username is required.")
        if not email:
            raise BadRequestError("Email is required.")
        if not password:
            raise BadRequestError("Password is required.")

        try:
            user = User(
                name=name,
                username=username,
                email=email,
                role=User.ROLE_RELATIVE,
                face_video_path=face_video_path,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            user.set_password(password)
            return user.save()
        except NotUniqueError:
            raise ConflictError("A user with this email or username already exists.")
        except ValidationError as e:
            raise BadRequestError(f"Invalid data: {e}")

    @staticmethod
    def register_caregiver(name: str, username: str, email: str, password: str, age: int, national_id: str, cv_path: str = None, face_video_path: str = None) -> User:
        name = (name or "").strip()
        username = (username or "").strip().lower()
        email = (email or "").strip().lower()
        national_id = (national_id or "").strip()
        if not name:
            raise BadRequestError("Name is required.")
        if not username:
            raise BadRequestError("Username is required.")
        if not email:
            raise BadRequestError("Email is required.")
        if not password:
            raise BadRequestError("Password is required.")
        if not age or age < 18:
            raise BadRequestError("Age must be at least 18.")
        if not national_id:
            raise BadRequestError("National ID is required.")

        try:
            user = User(
                name=name,
                username=username,
                email=email,
                role=User.ROLE_CAREGIVER,
                age=age,
                national_id=national_id,
                cv_path=cv_path,
                face_video_path=face_video_path,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            user.set_password(password)
            return user.save()
        except NotUniqueError:
            raise ConflictError("A user with this email or username already exists.")
        except ValidationError as e:
            raise BadRequestError(f"Invalid data: {e}")

    @staticmethod
    def search_users(query: str, role: str = None) -> List[User]:
        """Search users by username (case-insensitive partial match)."""
        filters = {"username__icontains": query.strip().lower()}
        if role:
            filters["role"] = role.strip().upper()
        return list(User.objects(**filters).order_by("username")[:20])

    @staticmethod
    def authenticate(email: str, password: str) -> User:
        email = (email or "").strip().lower()
        if not email or not password:
            raise BadRequestError("Email and password are required.")
        user = User.objects(email=email).first()
        if not user or not user.check_password(password):
            raise BadRequestError("Invalid email or password.")
        return user

    @staticmethod
    def get_user_by_id(user_id: str) -> User:
        return get_user(user_id)

    @staticmethod
    def list_users(role: Optional[str] = None) -> List[User]:
        if role:
            role = role.strip().upper()
            return list(User.objects(role=role).order_by("-created_at"))
        return list(User.objects.order_by("-created_at"))
