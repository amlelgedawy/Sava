from rest_framework import serializers


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(max_length=128, write_only=True)


class RelativeSignUpSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=200)
    username = serializers.CharField(max_length=50)
    email = serializers.EmailField()
    password = serializers.CharField(max_length=128, write_only=True)
    confirm_password = serializers.CharField(max_length=128, write_only=True)

    def validate(self, data):
        if data["password"] != data["confirm_password"]:
            raise serializers.ValidationError("Passwords do not match.")
        return data


class CaregiverSignUpSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=200)
    username = serializers.CharField(max_length=50)
    email = serializers.EmailField()
    password = serializers.CharField(max_length=128, write_only=True)
    confirm_password = serializers.CharField(max_length=128, write_only=True)
    age = serializers.IntegerField(min_value=18)
    national_id = serializers.CharField(max_length=50)
    cv = serializers.FileField(required=False)

    def validate_cv(self, value):
        if value:
            if not value.name.lower().endswith(".pdf"):
                raise serializers.ValidationError("CV must be a PDF file.")
            if value.content_type not in ("application/pdf",):
                raise serializers.ValidationError("CV must be a PDF file.")
        return value

    def validate(self, data):
        if data["password"] != data["confirm_password"]:
            raise serializers.ValidationError("Passwords do not match.")
        return data
