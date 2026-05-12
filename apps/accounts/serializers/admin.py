from rest_framework import serializers


class SetSalarySerializer(serializers.Serializer):
    salary_per_hour = serializers.FloatField(min_value=0)
