from rest_framework import serializers
from apps.monitoring.models import User 

class UserCreateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length= 200)
    email = serializers.EmailField()
    role = serializers.ChoiceField(choices=[User.ROLE_PATIENT, User.ROLE_CAREGIVER])
    password = serializers.CharField(max_length=128, required=False, write_only=True)
    
    def validateRole(self, value:str):
        return value.strip().upper()

    def validate(self, data):
        if data.get("role", "").upper() == User.ROLE_CAREGIVER and not data.get("password"):
            raise serializers.ValidationError("Password is required for caregivers.")
        return data
    

class UserUpdateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length= 200, required= False)
    password = serializers.CharField(max_length=128, required=False, write_only=True)

class UserResponseSerializer(serializers.Serializer):
    id = serializers.CharField()
    name = serializers.CharField()
    email = serializers.EmailField()
    role = serializers.CharField()
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()
    
class LinkCaregiverSerializer(serializers.Serializer):
    patient_id = serializers.CharField()
    caregiver_id = serializers.CharField()


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(max_length=128)

class AlertUpdateSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=["NEW", "SEEN"])