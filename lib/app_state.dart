import 'package:flutter/material.dart';
import 'models/patient_models.dart';
import 'services/live_sensor_service.dart';

enum AlertType {
  none,
  fall,
  sharpObject,
  unknownPerson,
  wandering,
  bathroomTimeout,
}

class AppState {
  static final ValueNotifier<int> currentNavIndex = ValueNotifier(0);
  static final ValueNotifier<int> heartRate = ValueNotifier(
    LiveSensorService.currentBpm,
  );
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

  static String get alertMessage {
    if (heartRate.value == 0) return "Emergency: No Heartbeat!";
    if (heartRate.value > 120) return "Alert: High Heart Rate";
    switch (alertStatus.value) {
      case AlertType.fall:
        return "Emergency: Fall Detected";
      case AlertType.sharpObject:
        return "AI Alert: Sharp Object Detected";
      case AlertType.unknownPerson:
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
