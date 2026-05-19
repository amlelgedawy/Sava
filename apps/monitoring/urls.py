from django.urls import path
from apps.monitoring.views import FrameIngestView
from apps.monitoring.views_alerts import AlertDetailView, AlertsListView
from apps.monitoring.views_person_tracking import PersonTrackingView, ActivePersonsView, CleanupPersonsView
from apps.monitoring.views_activity import ActivityEventView, ActivityHistoryView, PatientLookupView
from apps.monitoring.views_object_detection import ObjectDetectionEventView, ObjectDetectionFrameView
from apps.monitoring.views_stream import PushFrameView, LiveStreamView, AIResultView, ActivityLogView

urlpatterns = [
    path("frames/ingest", FrameIngestView.as_view(), name="frame_ingest"),
    
    # Person tracking endpoints
    path("person-tracking/track", PersonTrackingView.as_view(), name="person_tracking"),
    path("person-tracking/active", ActivePersonsView.as_view(), name="active_persons"),
    path("person-tracking/cleanup", CleanupPersonsView.as_view(), name="cleanup_persons"),
    
    # Activity recognition endpoints
    path("activity-recognition/event", ActivityEventView.as_view(), name="activity_event"),
    path("activity-recognition/history", ActivityHistoryView.as_view(), name="activity_history"),
    path("activity-recognition/patient-lookup", PatientLookupView.as_view(), name="patient_lookup"),
    
    # Object detection endpoints
    path("object-detection/event", ObjectDetectionEventView.as_view(), name="object_detection_event"),
    path("object-detection/detect", ObjectDetectionFrameView.as_view(), name="object_detection_frame"),
    
    path("alerts", AlertsListView.as_view(), name="alerts_list"),
    path("alerts/<str:alert_id>", AlertDetailView.as_view(), name="alert_detail"),

    # Stream pipeline
    path("stream/push-frame", PushFrameView.as_view(), name="stream_push_frame"),
    path("stream/live/<str:patient_id>", LiveStreamView.as_view(), name="stream_live"),
    path("stream/ai-result", AIResultView.as_view(), name="stream_ai_result"),
    path("stream/activity-log/<str:patient_id>", ActivityLogView.as_view(), name="stream_activity_log"),
]
