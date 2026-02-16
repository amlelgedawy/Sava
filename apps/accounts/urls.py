from django.urls import path
from apps.accounts.views import (
    UsersListCreateView,
    UserDetailView,
    LinkCaregiverToPatientView,
    PatientCaregiversView,
    CaregiverPatientsView,
)

urlpatterns = [
    path("users", UsersListCreateView.as_view(), name="users_list_create"),
    path("users/<str:user_id>", UserDetailView.as_view(), name="user_detail"),

    path(
        "patients/<str:patient_id>/caregivers/<str:caregiver_id>",
        LinkCaregiverToPatientView.as_view(),
        name="link_caregiver_patient",
    ),
    path(
        "patients/<str:patient_id>/caregivers",
        PatientCaregiversView.as_view(),
        name="patient_caregivers",
    ),
    path(
        "caregivers/<str:caregiver_id>/patients",
        CaregiverPatientsView.as_view(),
        name="caregiver_patients",
    ),
]
