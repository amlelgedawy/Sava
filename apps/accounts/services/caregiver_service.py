from datetime import datetime
from typing import Optional, List

from bson import ObjectId

from apps.monitoring.models import (
    User, Patient, PatientRelativeLink, CaregiverContract,
    MedicationSchedule, MedicationEntry,
)
from apps.accounts.services.base import (
    get_user, get_patient,
    NotFoundError, BadRequestError, ConflictError, ForbiddenError,
)
from apps.accounts.services.relative_service import RelativeService


class CaregiverService:

    # Contract flow

    @staticmethod
    def list_available_caregivers() -> List[User]:
        all_cg = User.objects(role=User.ROLE_CAREGIVER).order_by("name")
        available = []
        for cg in all_cg:
            active = CaregiverContract.objects(
                caregiver=cg, status=CaregiverContract.STATUS_ACTIVE
            ).count()
            if active < 4:
                available.append(cg)
        return available

    @staticmethod
    def send_caregiver_offer(patient_id: str, requester_id: str, caregiver_id: str) -> CaregiverContract:
        patient = get_patient(patient_id)
        requester = get_user(requester_id)
        RelativeService.assert_primary_relative(patient, requester)

        caregiver = get_user(caregiver_id)
        if caregiver.role != User.ROLE_CAREGIVER:
            raise BadRequestError("Target user is not a CAREGIVER.")

        active = CaregiverContract.objects(
            patient=patient,
            status__in=[CaregiverContract.STATUS_ACTIVE, CaregiverContract.STATUS_PENDING],
        ).first()
        if active:
            raise ConflictError(
                "Patient already has an active or pending caregiver contract. "
                "End the current contract first."
            )

        cg_active = CaregiverContract.objects(
            caregiver=caregiver, status=CaregiverContract.STATUS_ACTIVE
        ).count()
        if cg_active >= 4:
            raise BadRequestError("This caregiver already manages 4 patients.")

        return CaregiverContract(
            patient=patient, caregiver=caregiver,
            offered_by=requester,
            status=CaregiverContract.STATUS_PENDING,
            created_at=datetime.utcnow(),
        ).save()

    @staticmethod
    def respond_to_offer(contract_id: str, caregiver_id: str, action: str) -> CaregiverContract:
        try:
            contract = CaregiverContract.objects.get(id=ObjectId(contract_id))
        except Exception:
            raise NotFoundError("Contract not found.")

        try:
            caregiver_oid = ObjectId(caregiver_id)
        except Exception:
            raise BadRequestError("Invalid caregiver_id.")

        if contract.caregiver.id != caregiver_oid:
            raise ForbiddenError("Only the offered caregiver can respond.")
        if contract.status != CaregiverContract.STATUS_PENDING:
            raise BadRequestError("This contract is no longer pending.")

        action = action.strip().upper()
        if action == "ACCEPT":
            contract.status = CaregiverContract.STATUS_ACTIVE
            contract.accepted_at = datetime.utcnow()
        elif action == "DECLINE":
            contract.status = CaregiverContract.STATUS_DECLINED
        else:
            raise BadRequestError("Action must be ACCEPT or DECLINE.")

        contract.save()
        return contract

    @staticmethod
    def end_contract(contract_id: str, user_id: str) -> CaregiverContract:
        try:
            contract = CaregiverContract.objects.get(id=ObjectId(contract_id))
        except Exception:
            raise NotFoundError("Contract not found.")

        if contract.status != CaregiverContract.STATUS_ACTIVE:
            raise BadRequestError("Only active contracts can be ended.")

        user = get_user(user_id)
        is_caregiver = contract.caregiver.id == user.id
        is_primary = PatientRelativeLink.objects(
            patient=contract.patient, relative=user,
            role_type=PatientRelativeLink.ROLE_PRIMARY,
        ).first() is not None

        if not is_caregiver and not is_primary:
            raise ForbiddenError("Only the caregiver or a primary relative can end a contract.")

        contract.status = CaregiverContract.STATUS_ENDED
        contract.ended_at = datetime.utcnow()
        contract.save()
        return contract

    @staticmethod
    def get_patients_for_caregiver(caregiver_id: str) -> List[Patient]:
        caregiver = get_user(caregiver_id)
        if caregiver.role != User.ROLE_CAREGIVER:
            raise BadRequestError("User is not a CAREGIVER.")
        contracts = CaregiverContract.objects(
            caregiver=caregiver.id, status=CaregiverContract.STATUS_ACTIVE
        )
        return [c.patient for c in contracts]

    @staticmethod
    def get_caregiver_for_patient(patient_id: str) -> Optional[User]:
        patient = get_patient(patient_id)
        contract = CaregiverContract.objects(
            patient=patient, status=CaregiverContract.STATUS_ACTIVE
        ).first()
        return contract.caregiver if contract else None

    @staticmethod
    def get_contracts_for_caregiver(caregiver_id: str, status_filter: str = None) -> List[CaregiverContract]:
        caregiver = get_user(caregiver_id)
        if caregiver.role != User.ROLE_CAREGIVER:
            raise BadRequestError("User is not a CAREGIVER.")
        q = CaregiverContract.objects(caregiver=caregiver.id)
        if status_filter:
            q = q.filter(status=status_filter.strip().upper())
        return list(q.order_by("-created_at"))

    # Alert recipients

    @staticmethod
    def get_alert_recipients(patient_id: str) -> List[User]:
        patient = get_patient(patient_id)
        recipients = []

        contract = CaregiverContract.objects(
            patient=patient, status=CaregiverContract.STATUS_ACTIVE
        ).first()
        if contract:
            recipients.append(contract.caregiver)

        links = PatientRelativeLink.objects(patient=patient)
        for link in links:
            recipients.append(link.relative)

        return recipients

    # Medication schedule

    @staticmethod
    def get_medication_schedule(patient_id: str) -> Optional[MedicationSchedule]:
        patient = get_patient(patient_id)
        return MedicationSchedule.objects(patient=patient).first()

    @staticmethod
    def upsert_medication_schedule(patient_id: str, user_id: str, entries: List[dict]) -> MedicationSchedule:
        patient = get_patient(patient_id)
        user = get_user(user_id)

        is_caregiver = (
            user.role == User.ROLE_CAREGIVER
            and CaregiverContract.objects(
                patient=patient, caregiver=user,
                status=CaregiverContract.STATUS_ACTIVE,
            ).first() is not None
        )
        is_primary = PatientRelativeLink.objects(
            patient=patient, relative=user,
            role_type=PatientRelativeLink.ROLE_PRIMARY,
        ).first() is not None

        if not is_caregiver and not is_primary:
            raise ForbiddenError(
                "Only the assigned caregiver or a primary relative can edit the medication schedule."
            )

        med_entries = [MedicationEntry(**e) for e in entries]

        schedule = MedicationSchedule.objects(patient=patient).first()
        if schedule:
            schedule.entries = med_entries
            schedule.updated_by = user
            schedule.updated_at = datetime.utcnow()
            schedule.save()
        else:
            schedule = MedicationSchedule(
                patient=patient, entries=med_entries,
                created_by=user, updated_by=user,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            ).save()

        return schedule
