import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../app_state.dart';
import 'database_service.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class ApiService {
  // Object detection server (our YOLO server)
  static const String _objectDetectionUrl = "http://127.0.0.1:5001";

  // Face recognition server (friend's AI server)
  static const String _faceAiUrl = "http://127.0.0.1:5000";

  // ==========================================================
  // OBJECT DETECTION — POST /detect to port 5001
  // ==========================================================
  static Future<void> detectObjects(Uint8List frameBytes) async {
    try {
      final formData = html.FormData();
      final blob = html.Blob([frameBytes], 'image/jpeg');
      formData.appendBlob('frame', blob, 'frame.jpg');

      final xhr = html.HttpRequest();
      final completer = Completer<void>();

      xhr.open('POST', '$_objectDetectionUrl/detect');
      xhr.onLoad.listen((_) {
        if (xhr.status == 200) {
          try {
            _handleDetectionResponse(xhr.responseText ?? '{}');
          } catch (_) {
            AppState.detectedObjects.value = [];
          }
        } else {
          AppState.detectedObjects.value = [];
        }
        completer.complete();
      });
      xhr.onError.listen((_) {
        AppState.detectedObjects.value = [];
        completer.complete();
      });

      xhr.send(formData);
      await completer.future;
    } catch (_) {
      AppState.detectedObjects.value = [];
    }
  }

  static void _handleDetectionResponse(String responseText) {
    final data = json.decode(responseText) as Map<String, dynamic>;
    final rawDetections = data['detections'] as List<dynamic>? ?? [];

    final List<DetectedObject> objects = [];
    bool hasDangerousObject = false;

    const highDanger = ['knife', 'syringe'];
    const mediumDanger = ['scissors', 'fork', 'hammer', 'screwdriver'];

    for (final raw in rawDetections) {
      final detection = raw as Map<String, dynamic>;
      final label = (detection['label'] as String? ?? 'unknown').toLowerCase();
      final confidence = (detection['confidence'] as num? ?? 0.0).toDouble();
      final box = detection['box'] as Map<String, dynamic>?;

      objects.add(
        DetectedObject(
          label: label,
          confidence: confidence,
          top: box != null ? (box['y1'] as num? ?? 0.0).toDouble() : 0.0,
          left: box != null ? (box['x1'] as num? ?? 0.0).toDouble() : 0.0,
          bottom: box != null ? (box['y2'] as num? ?? 1.0).toDouble() : 1.0,
          right: box != null ? (box['x2'] as num? ?? 1.0).toDouble() : 1.0,
        ),
      );

      if (highDanger.contains(label) || mediumDanger.contains(label)) {
        hasDangerousObject = true;
      }
    }

    AppState.detectedObjects.value = objects;

    if (hasDangerousObject) {
      if (AppState.alertStatus.value != AlertType.sharpObject) {
        AppState.logAlert(AlertType.sharpObject);
      }
      AppState.alertStatus.value = AlertType.sharpObject;
    } else if (AppState.alertStatus.value == AlertType.sharpObject) {
      AppState.alertStatus.value = AlertType.none;
    }
  }

  // ==========================================================
  // FACE RECOGNITION — POST /analyze-face to port 5000
  // ==========================================================
  static Future<void> analyzeFace(Uint8List frameBytes) async {
    try {
      final patientId = AppState.patientId.value ?? '1';

      final formData = html.FormData();
      final blob = html.Blob([frameBytes], 'image/jpeg');
      formData.appendBlob('frame', blob, 'frame.jpg');
      formData.append('patient_id', patientId);

      final xhr = html.HttpRequest();
      final completer = Completer<void>();

      xhr.open('POST', '$_faceAiUrl/analyze-face');
      xhr.onLoad.listen((_) {
        if (xhr.status == 200) {
          try {
            _handleFaceResponse(xhr.responseText ?? '{}');
          } catch (_) {
            AppState.detectedFaces.value = [];
          }
        } else {
          AppState.detectedFaces.value = [];
        }
        completer.complete();
      });
      xhr.onError.listen((_) {
        AppState.detectedFaces.value = [];
        completer.complete();
      });

      xhr.send(formData);
      await completer.future;
    } catch (_) {
      AppState.detectedFaces.value = [];
    }
  }

  static void _handleFaceResponse(String responseText) {
    final data = json.decode(responseText) as Map<String, dynamic>;
    final payload = data['payload'] as Map<String, dynamic>?;

    if (payload == null) {
      AppState.detectedFaces.value = [];
      return;
    }

    final isKnown = payload['known'] as bool? ?? false;
    final name = payload['person_name'] as String?;

    // Build face detection result
    // Face AI server may return location if available
    final location = payload['location'] as Map<String, dynamic>?;

    final face = DetectedFace(
      name: name,
      isKnown: isKnown,
      top: location != null ? (location['top'] as num? ?? 0.2).toDouble() : 0.2,
      left: location != null
          ? (location['left'] as num? ?? 0.3).toDouble()
          : 0.3,
      bottom: location != null
          ? (location['bottom'] as num? ?? 0.8).toDouble()
          : 0.8,
      right: location != null
          ? (location['right'] as num? ?? 0.7).toDouble()
          : 0.7,
    );

    AppState.detectedFaces.value = [face];

    // Trigger unknown face alert
    if (!isKnown) {
      if (AppState.alertStatus.value != AlertType.unknown_face) {
        AppState.logAlert(AlertType.unknown_face);
      }
      AppState.alertStatus.value = AlertType.unknown_face;
    } else if (AppState.alertStatus.value == AlertType.unknown_face) {
      AppState.alertStatus.value = AlertType.none;
    }
  }

  // ==========================================================
  // SIMULATION HELPERS
  // ==========================================================
  static void simulateHeartRate(int bpm) {
    AppState.heartRate.value = bpm;
    if (bpm == 0 || bpm > 120) {
      AppState.alertStatus.value = AlertType.fall;
    } else {
      AppState.alertStatus.value = AlertType.none;
    }
  }

  static void processAiDetection(AlertType currentAlert) {
    switch (currentAlert) {
      case AlertType.none:
        AppState.alertStatus.value = AlertType.fall;
        break;
      case AlertType.fall:
        AppState.alertStatus.value = AlertType.sharpObject;
        break;
      case AlertType.sharpObject:
        AppState.alertStatus.value = AlertType.unknown_face;
        break;
      case AlertType.unknown_face:
        AppState.alertStatus.value = AlertType.bathroomTimeout;
        break;
      case AlertType.bathroomTimeout:
        AppState.alertStatus.value = AlertType.none;
        break;
      default:
        AppState.alertStatus.value = AlertType.none;
    }
  }

  static void onFallDetected() {
    AppState.alertStatus.value = AlertType.fall;
  }

  static void clearAlerts() {
    AppState.alertStatus.value = AlertType.none;
  }

  static void onActivityDetected(String activityName, IconData icon) {
    DatabaseService.addNewActivity(activityName, icon);
  }
}
