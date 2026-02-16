from rest_framework import serializers

class FrameIngestSerializer(serializers.Serializer):
    patient_id = serializers.CharField()
    frame = serializers.ImageField()
    camera_id = serializers.CharField(required=False, allow_blank=True)
    timestamp = serializers.CharField(required=False, allow_blank=True)

class SimulateEventSerializer(serializers.Serializer):
    patient_id = serializers.CharField()
    event_type = serializers.ChoiceField(choices=["FACE", "FALL", "OBJECT"], default="FACE")
    confidence = serializers.FloatField(min_value=0.0, max_value=1.0, default=0.95)

    # payload is optional; for FACE you’ll pass {"known": false}
    payload = serializers.DictField(required=False, default=dict)
    
class AlertUpdateSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=["NEW", "SEEN"])