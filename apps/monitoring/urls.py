from django.urls import path
from apps.monitoring.views import FrameIngestView
from apps.monitoring.views_alerts import AlertDetailView, AlertsListView

urlpatterns = [
    path("frames/ingest", FrameIngestView.as_view(), name="frame_ingest"),
    
    path("alerts", AlertsListView.as_view(), name="alerts_list"),   
    path("alerts/<str:alert_id>", AlertDetailView.as_view(), name="alert_detail"),
]
