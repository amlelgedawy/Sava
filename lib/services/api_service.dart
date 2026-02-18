import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../app_state.dart';
import 'database_service.dart';
// DetectedFace is defined in app_state.dart and used by _handleIngestResponse

// ============================================================
//  ApiService
//  Handles ONLY AI detection results and simulation helpers.
//  Zero database logic lives here.
//
//  All database work (auth, patient, alerts) → DatabaseService
//  All AppState reads/writes from AI results → here
// ============================================================

// Web-specific imports for frame capture
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class ApiService {
  // ==========================================================
  // AI DETECTION HANDLERS
  // These are called by your AI modules when they detect
  // something. They write the result into AppState so every
  // screen updates automatically.
  // ==========================================================

  /// Called by your activity-recognition AI when it detects
  /// what the patient is doing. Adds an entry to the activity log.
  static void onActivityDetected(String activityName, IconData icon) {
    DatabaseService.addNewActivity(activityName, icon);
  }

  /// Called by your fall-detection AI.
  static void onFallDetected() {
    AppState.alertStatus.value = AlertType.fall;
  }

  /// Called by your object-detection AI when a sharp object is seen.
  static void onSharpObjectDetected() {
    AppState.alertStatus.value = AlertType.sharpObject;
  }

  /// Called by your face-recognition AI when an unknown face appears.
  static void onUnknownFaceDetected() {
    AppState.alertStatus.value = AlertType.unknown_face;
  }

  /// Called by your sensor system when the patient is in the
  /// bathroom too long.
  static void onBathroomTimeout() {
    AppState.alertStatus.value = AlertType.bathroomTimeout;
  }

  /// Called by your sensor system when the patient wanders
  /// outside a safe zone.
  static void onWanderingDetected() {
    AppState.alertStatus.value = AlertType.wandering;
  }

  /// Called by your heart-rate sensor with the latest BPM reading.
  static void updateHeartRate(int bpm) {
    AppState.heartRate.value = bpm;
    if (bpm == 0 || bpm > 120) {
      AppState.alertStatus.value = AlertType.fall;
    }
  }

  /// Clears any active alert (e.g. after caregiver acknowledges it).
  static void clearAlerts() {
    AppState.alertStatus.value = AlertType.none;
  }

  // ==========================================================
  // AI FACE SERVER INTEGRATION
  // Sends a frame (as JPEG bytes) to the face-recognition AI
  // and updates AppState based on the result.
  // Call this from your camera loop or wherever you capture frames.
  // ==========================================================

  static const String _faceAiUrl = "http://localhost:5000";

  /// Sends [frameBytes] (JPEG) to the AI face server and triggers
  /// [onUnknownFaceDetected] if an unknown person is seen.
  /// [patientId] is used by the server to scope the check.
  static Future<void> analyzeFaceFrame(
    Uint8List frameBytes, {
    String patientId = "1",
  }) async {
    try {
      final formData = html.FormData();
      final blob = html.Blob([frameBytes], 'image/jpeg');
      formData.appendBlob('frame', blob, 'frame.jpg');
      formData.append('patient_id', patientId);

      final xhr = html.HttpRequest();
      // ignore: close_sinks
      final completer = Completer<void>();

      xhr.open('POST', '$_faceAiUrl/analyze-face');
      xhr.onLoad.listen((_) {
        if (xhr.status == 200) {
          try {
            final data = json.decode(xhr.responseText ?? '{}');
            final payload = data['payload'] as Map<String, dynamic>?;
            final known = payload?['known'] as bool? ?? true;
            if (!known) {
              onUnknownFaceDetected();
            }
          } catch (_) {}
        }
        completer.complete();
      });
      xhr.onError.listen((_) => completer.complete());
      xhr.send(formData);
      await completer.future;
    } catch (_) {
      // Silently ignore - face check is best-effort
    }
  }

  // ==========================================================
  // FRAME INGESTION  (called by VisionPage every ~2 seconds)
  // Sends a JPEG frame to Django /api/frames/ingest, which runs
  // the face-recognition AI and returns bounding boxes + names.
  // This method:
  //   1. POSTs the frame to Django
  //   2. Parses every detected face from the response
  //   3. Writes them into AppState.detectedFaces  → VisionPage draws AR boxes
  //   4. If ANY face is unknown → triggers onUnknownFaceDetected()
  // ==========================================================

  static const String _djangoUrl = "http://127.0.0.1:8000/api";

  /// Main entry point called by VisionPage.
  /// [frameBytes] – raw JPEG bytes from the camera.
  /// [patientId]  – scopes the request on the Django side.
  static Future<void> ingestFrame(
    Uint8List frameBytes, {
    String patientId = "1",
  }) async {
    try {
      final formData = html.FormData();
      final blob = html.Blob([frameBytes], 'image/jpeg');
      formData.appendBlob('frame', blob, 'frame.jpg');
      formData.append('patient_id', patientId);
      // Also send caregiver_id so Django can look up the patient if needed
      final caregiverId = AppState.caregiverId.value ?? '';
      formData.append('caregiver_id', caregiverId);

      final xhr = html.HttpRequest();
      final completer = Completer<void>();

      xhr.open('POST', '$_djangoUrl/frames/ingest/');
      xhr.onLoad.listen((_) {
        // Django returns 201 Created on success (not 200)
        if (xhr.status == 200 || xhr.status == 201) {
          try {
            _handleIngestResponse(xhr.responseText ?? '{}');
          } catch (_) {
            AppState.detectedFaces.value = [];
          }
        } else {
          // Server error — clear stale boxes so the UI doesn't freeze
          AppState.detectedFaces.value = [];
        }
        completer.complete();
      });
      xhr.onError.listen((_) {
        // Network error — clear stale boxes
        AppState.detectedFaces.value = [];
        completer.complete();
      });

      xhr.send(formData);
      await completer.future;
    } catch (_) {
      AppState.detectedFaces.value = [];
    }
  }

  /// Parses the Django /api/frames/ingest JSON response and updates AppState.
  ///
  /// Expected response shape (Django side should return this):
  /// {
  ///   "faces": [
  ///     {
  ///       "known": true,
  ///       "name": "john",          // null or missing if unknown
  ///       "location": {            // normalized 0.0–1.0
  ///         "top": 0.1, "left": 0.2, "bottom": 0.4, "right": 0.5
  ///       }
  ///     }
  ///   ]
  /// }
  static void _handleIngestResponse(String responseText) {
    final data = json.decode(responseText) as Map<String, dynamic>;
    final rawFaces = data['faces'] as List<dynamic>? ?? [];

    final List<DetectedFace> faces = [];
    bool hasUnknown = false;

    for (final raw in rawFaces) {
      final face = raw as Map<String, dynamic>;
      final isKnown = face['known'] as bool? ?? false;
      final name = face['name'] as String?;
      final loc = face['location'] as Map<String, dynamic>?;

      // If AI returned no bounding box, use a centered default so the box still shows
      faces.add(
        DetectedFace(
          name: name,
          isKnown: isKnown,
          top: loc != null ? (loc['top'] as num? ?? 0.2).toDouble() : 0.2,
          left: loc != null ? (loc['left'] as num? ?? 0.3).toDouble() : 0.3,
          bottom: loc != null ? (loc['bottom'] as num? ?? 0.8).toDouble() : 0.8,
          right: loc != null ? (loc['right'] as num? ?? 0.7).toDouble() : 0.7,
        ),
      );

      if (!isKnown) hasUnknown = true;
    }

    // Write face list → VisionPage redraws AR boxes immediately
    AppState.detectedFaces.value = faces;

    // Trigger alert if any unknown face was found
    if (hasUnknown) {
      onUnknownFaceDetected();
    } else if (AppState.alertStatus.value == AlertType.unknown_face) {
      // Clear the unknown-face alert once all faces are recognised again
      AppState.alertStatus.value = AlertType.none;
    }
  }

  // ==========================================================
  // SIMULATION HELPERS
  // For testing in VS Code without real hardware.
  // These buttons exist on the home screen (the flask/speed icons).
  // ==========================================================

  /// Simulates a heart-rate reading. Used by the speed-icon
  /// button on the home screen to toggle between normal and
  /// critical BPM for testing.
  static void simulateHeartRate(int bpm) {
    AppState.heartRate.value = bpm;
    if (bpm == 0 || bpm > 120) {
      AppState.alertStatus.value = AlertType.fall;
    } else {
      AppState.alertStatus.value = AlertType.none;
    }
  }

  /// Cycles through all alert types one by one. Used by the
  /// flask-icon button on the home screen to test the alert UI.
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
}
