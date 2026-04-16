from django.urls import path
from apps.monitoring.views import FrameIngestView
from apps.monitoring.views_alerts import AlertDetailView, AlertsListView
from apps.monitoring.views_person_tracking import PersonTrackingView, ActivePersonsView, CleanupPersonsView

urlpatterns = [
    path("frames/ingest", FrameIngestView.as_view(), name="frame_ingest"),
    
    # Person tracking endpoints
    path("person-tracking/track", PersonTrackingView.as_view(), name="person_tracking"),
    path("person-tracking/active", ActivePersonsView.as_view(), name="active_persons"),
    path("person-tracking/cleanup", CleanupPersonsView.as_view(), name="cleanup_persons"),
    
    path("alerts", AlertsListView.as_view(), name="alerts_list"),   
    path("alerts/<str:alert_id>", AlertDetailView.as_view(), name="alert_detail"),
]
