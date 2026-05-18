import 'package:flutter/material.dart';
import 'models/patient_models.dart';
import 'models/user_models.dart';
import 'services/database_service.dart';

// ── Detected Object Result ────────────────────────────────────────────────────
class DetectedObject {
  final String label;
  final double confidence;
  final double top;
  final double left;
  final double bottom;
  final double right;

  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });
}

// ── Alert History Entry ───────────────────────────────────────────────────────
class AlertEntry {
  final AlertType type;
  final String message;
  final String time;
  final String? backendId;

  const AlertEntry({
    required this.type,
    required this.message,
    required this.time,
    this.backendId,
  });
}

// Keep DetectedFace for backwards compatibility
class DetectedFace {
  final String? name;
  final bool isKnown;
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

// ── Activity Recognition Result ───────────────────────────────────────────────
class ActivityResult {
  final String? activity; // e.g. "WALK", "FALL", null = uncertain
  final double confidence;
  final bool fallAlert;
  final bool wandering;
  final int bufferProgress; // 0..64
  final int bufferTarget;
  final List<DetectedObject> personBoxes;

  const ActivityResult({
    this.activity,
    required this.confidence,
    required this.fallAlert,
    required this.wandering,
    required this.bufferProgress,
    required this.bufferTarget,
    required this.personBoxes,
  });

  static const ActivityResult empty = ActivityResult(
    activity: null,
    confidence: 0.0,
    fallAlert: false,
    wandering: false,
    bufferProgress: 0,
    bufferTarget: 64,
    personBoxes: [],
  );
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

  // ---- OBJECT DETECTION ----
  static final ValueNotifier<List<DetectedObject>> detectedObjects =
      ValueNotifier([]);

  // ---- FACE DETECTION (backwards compat) ----
  static final ValueNotifier<List<DetectedFace>> detectedFaces = ValueNotifier(
    [],
  );

  // ---- ACTIVITY RECOGNITION ----
  static final ValueNotifier<ActivityResult> activityResult = ValueNotifier(
    ActivityResult.empty,
  );

  // ---- ALERT HISTORY ----
  static final ValueNotifier<List<AlertEntry>> alertHistory = ValueNotifier([]);

  // ---- USER SESSION ----
  static final ValueNotifier<String?> userId = ValueNotifier(null);
  static final ValueNotifier<String?> caregiverId = ValueNotifier(null);
  static final ValueNotifier<String?> patientId = ValueNotifier(null);
  static final ValueNotifier<String> caregiverName = ValueNotifier("Caregiver");
  static final ValueNotifier<String> patientName = ValueNotifier("Patient");

  // ---- AUTH STATE ----
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);
  static final ValueNotifier<String?> authError = ValueNotifier(null);
  static final ValueNotifier<bool> isAuthLoading = ValueNotifier(false);

  // ---- ROLE & SESSION ----
  static final ValueNotifier<UserRole?> userRole = ValueNotifier(null);
  static final ValueNotifier<AppUser?> currentUser = ValueNotifier(null);

  // ---- ACTIONS ----
  static void addActivity(String title, IconData icon) {
    DatabaseService.addNewActivity(title, icon);
  }

  /// Call this whenever an alert is triggered to save it to history
  static void logAlert(AlertType type) {
    if (type == AlertType.none) return;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final entry = AlertEntry(
      type: type,
      message: _getAlertMessage(type),
      time: timeStr,
    );
    alertHistory.value = [...alertHistory.value, entry];
  }

  static String _getAlertMessage(AlertType type) {
    switch (type) {
      case AlertType.fall:
        return "Emergency: Fall Detected";
      case AlertType.sharpObject:
        return "AI Alert: Dangerous Object Detected";
      case AlertType.unknown_face:
        return "AI Alert: Unknown Face Detected";
      case AlertType.wandering:
        return "Sensor Alert: Patient Wandering";
      case AlertType.bathroomTimeout:
        return "Sensor Alert: Bathroom Timeout";
      default:
        return "Alert";
    }
  }

  static String get alertMessage {
    switch (alertStatus.value) {
      case AlertType.fall:
        return "Emergency: Fall Detected";
      case AlertType.sharpObject:
        return "AI Alert: Dangerous Object Detected";
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
