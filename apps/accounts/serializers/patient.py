from rest_framework import serializers
from apps.monitoring.models import Patient


class PatientCreateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=200)
    date_of_birth = serializers.DateField()
    gender = serializers.ChoiceField(choices=[Patient.GENDER_MALE, Patient.GENDER_FEMALE])
    current_medication = serializers.CharField(required=False, allow_blank=True)


class PatientUpdateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=200, required=False)
    date_of_birth = serializers.DateField(required=False)
    gender = serializers.ChoiceField(
        choices=[Patient.GENDER_MALE, Patient.GENDER_FEMALE], required=False
    )
    current_medication = serializers.CharField(required=False, allow_blank=True)


class PatientResponseSerializer(serializers.Serializer):
    id = serializers.CharField()
    name = serializers.CharField()
    date_of_birth = serializers.DateTimeField()
    age = serializers.IntegerField()
    gender = serializers.CharField()
    current_medication = serializers.CharField(allow_null=True)
    face_video_path = serializers.CharField(allow_null=True)
    created_by = serializers.CharField()
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()
