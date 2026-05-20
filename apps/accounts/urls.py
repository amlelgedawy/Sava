from django.urls import path
from apps.accounts.views import (
    LoginView,
    RelativeSignUpView,
    CaregiverSignUpView,
    UserDetailView,
    UserSearchView,
    PatientListCreateView,
    PatientDetailView,
    PatientRelativesView,
    RelativeRoleView,
    AvailableCaregiversView,
    CaregiverOfferView,
    ContractRespondView,
    ContractEndView,
    CaregiverPatientsView,
    CaregiverContractsView,
    PatientCaregiverView,
    MedicationScheduleView,
    AdminCaregiversView,
    AdminSetSalaryView,
    AdminDeleteUserView,
    AdminUsersListView,
    AdminRejectCaregiverView,
    AdminChangeRelativeRoleView,
)

urlpatterns = [
    # Auth
    path("auth/login", LoginView.as_view(), name="login"),
    path("auth/signup/relative", RelativeSignUpView.as_view(), name="signup_relative"),
    path("auth/signup/caregiver", CaregiverSignUpView.as_view(), name="signup_caregiver"),

    # Users
    path("users/search", UserSearchView.as_view(), name="user_search"),
    path("users/<str:user_id>", UserDetailView.as_view(), name="user_detail"),

    # Patient profiles
    path("patients", PatientListCreateView.as_view(), name="patient_list_create"),
    path("patients/<str:patient_id>", PatientDetailView.as_view(), name="patient_detail"),

    # Relative management
    path("patients/<str:patient_id>/relatives", PatientRelativesView.as_view(), name="patient_relatives"),
    path("patients/<str:patient_id>/relatives/<str:relative_id>/role", RelativeRoleView.as_view(), name="relative_role"),

    # Caregiver contracts
    path("caregivers/available", AvailableCaregiversView.as_view(), name="available_caregivers"),
    path("patients/<str:patient_id>/caregiver-offer", CaregiverOfferView.as_view(), name="caregiver_offer"),
    path("contracts/<str:contract_id>/respond", ContractRespondView.as_view(), name="contract_respond"),
    path("contracts/<str:contract_id>/end", ContractEndView.as_view(), name="contract_end"),
    path("caregivers/<str:caregiver_id>/patients", CaregiverPatientsView.as_view(), name="caregiver_patients"),
    path("caregivers/<str:caregiver_id>/contracts", CaregiverContractsView.as_view(), name="caregiver_contracts"),
    path("patients/<str:patient_id>/caregiver", PatientCaregiverView.as_view(), name="patient_caregiver"),

    # Medication schedule
    path("patients/<str:patient_id>/medication", MedicationScheduleView.as_view(), name="medication_schedule"),

    # Admin
    path("admin/caregivers", AdminCaregiversView.as_view(), name="admin_caregivers"),
    path("admin/caregivers/<str:caregiver_id>/salary", AdminSetSalaryView.as_view(), name="admin_set_salary"),
    path("admin/users", AdminUsersListView.as_view(), name="admin_users_list"),
    path("admin/users/<str:user_id>", AdminDeleteUserView.as_view(), name="admin_delete_user"),
    path("admin/caregivers/<str:caregiver_id>/reject", AdminRejectCaregiverView.as_view(), name="admin_reject_caregiver"),
    path("admin/patients/<str:patient_id>/relatives/<str:relative_id>/role", AdminChangeRelativeRoleView.as_view(), name="admin_change_relative_role"),
]
