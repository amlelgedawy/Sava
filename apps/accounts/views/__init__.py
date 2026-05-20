from apps.accounts.views.views_auth import LoginView, RelativeSignUpView, CaregiverSignUpView, UserDetailView, UserSearchView
from apps.accounts.views.views_patient import PatientListCreateView, PatientDetailView
from apps.accounts.views.views_relative import PatientRelativesView, RelativeRoleView
from apps.accounts.views.views_caregiver import (
    AvailableCaregiversView, CaregiverOfferView, ContractRespondView,
    ContractEndView, CaregiverPatientsView, CaregiverContractsView,
    PatientCaregiverView, MedicationScheduleView,
)
from apps.accounts.views.views_admin import (
    AdminCaregiversView, AdminSetSalaryView, AdminDeleteUserView, AdminUsersListView,
    AdminRejectCaregiverView, AdminChangeRelativeRoleView,
)
