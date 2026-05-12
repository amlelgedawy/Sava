from rest_framework import serializers


class UserResponseSerializer(serializers.Serializer):
    id = serializers.CharField()
    name = serializers.CharField()
    username = serializers.CharField()
    email = serializers.EmailField()
    role = serializers.CharField()
    face_video_path = serializers.CharField(allow_null=True, required=False)
    # Caregiver fields
    age = serializers.IntegerField(allow_null=True, required=False)
    national_id = serializers.CharField(allow_null=True, required=False)
    cv_path = serializers.CharField(allow_null=True, required=False)
    salary_per_hour = serializers.FloatField(allow_null=True, required=False)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class AlertUpdateSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=["NEW", "SEEN", "DISMISSED"])
