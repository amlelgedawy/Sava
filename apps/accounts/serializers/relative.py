from rest_framework import serializers


class AddRelativeSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=50)
    role_type = serializers.ChoiceField(choices=["PRIMARY", "SECONDARY"])
