import 'package:flutter/material.dart';
import 'models/patient_models.dart';
import 'services/database_service.dart';

// ── Face Detection Result ─────────────────────────────────────────────────────
// Written by ApiService after each /api/frames/ingest response.
// Read by VisionPage to draw AR bounding boxes on the camera feed.
class DetectedFace {
  final String? name; // null = unknown face
  final bool isKnown;
  // Normalized coordinates (0.0–1.0) relative to the camera frame.
  // top-left origin, same convention as the Django response.
  final double top;
  final double left;
  final double bottom;
  final double right;

  const DetectedFace({
    required this.name,
    required this.isKnown,
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });
}

enum AlertType {
  none,
  fall,
  sharpObject,
  unknown_face,
  wandering,
  bathroomTimeout,
}

class AppState {
  static final ValueNotifier<int> currentNavIndex = ValueNotifier(0);
  static final ValueNotifier<int> heartRate = ValueNotifier(74);
  static final ValueNotifier<AlertType> alertStatus = ValueNotifier(
    AlertType.none,
  );

  static final ValueNotifier<Medication?> nextMedication = ValueNotifier(null);
  static final ValueNotifier<ActivityLog?> lastActivity = ValueNotifier(null);

  static final ValueNotifier<List<ActivityLog>> allActivityLogs = ValueNotifier(
    [],
  );
  static final ValueNotifier<List<Medication>> allMedications = ValueNotifier(
    [],
  );

  // ---- FACE DETECTION ----
  // Written by ApiService, read by VisionPage to draw AR boxes.
  static final ValueNotifier<List<DetectedFace>> detectedFaces = ValueNotifier(
    [],
  );

  // ---- USER SESSION ----
  static final ValueNotifier<String?> caregiverId = ValueNotifier(null);
  static final ValueNotifier<String?> patientId = ValueNotifier(null);
  static final ValueNotifier<String> caregiverName = ValueNotifier("Caregiver");
  static final ValueNotifier<String> patientName = ValueNotifier("Patient");

  // ---- AUTH STATE ----
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);
  static final ValueNotifier<String?> authError = ValueNotifier(null);
  static final ValueNotifier<bool> isAuthLoading = ValueNotifier(false);

  // ---- ACTIONS (AppState delegates to services) ----
  // Screen calls AppState.addActivity() → AppState calls DatabaseService
  static void addActivity(String title, IconData icon) {
    DatabaseService.addNewActivity(title, icon);
  }

  static String get alertMessage {
    switch (alertStatus.value) {
      case AlertType.fall:
        return "Emergency: Fall Detected";
      case AlertType.sharpObject:
        return "AI Alert: Sharp Object Detected";
      case AlertType.unknown_face:
        return "AI Alert: Unknown Face Detected";
      case AlertType.wandering:
        return "Sensor Alert: Patient Wandering";
      case AlertType.bathroomTimeout:
        return "Sensor Alert: Bathroom Timeout";
      default:
        return "All Systems Secure";
    }
  }
}
