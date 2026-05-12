from rest_framework import serializers


class CaregiverOfferSerializer(serializers.Serializer):
    caregiver_id = serializers.CharField()


class ContractActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=["ACCEPT", "DECLINE"])


class MedicationEntrySerializer(serializers.Serializer):
    medicine_name = serializers.CharField(max_length=200)
    time_to_consume = serializers.CharField(max_length=10)
    dosage = serializers.CharField(max_length=100, required=False, allow_blank=True)
    notes = serializers.CharField(max_length=500, required=False, allow_blank=True)


class MedicationScheduleSerializer(serializers.Serializer):
    entries = MedicationEntrySerializer(many=True)
