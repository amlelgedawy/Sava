import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_state.dart';
import 'database_service.dart';

class ApiService {
  static const String _baseUrl = "http://10.0.2.2:8000/api";

  // Object detection server
  static const String _objectDetectionUrl = "http://10.0.2.2:5002";

  // Face recognition server
  static const String _faceAiUrl = "http://10.0.2.2:5000";

  // Activity recognition server
  static const String _activityServerUrl = "http://10.0.2.2:5003";

  // AUTH

  /// POST /api/auth/login  → returns full user map or throws
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );
    final data = json.decode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) return data;
    throw data['detail'] ?? 'Login failed (${resp.statusCode})';
  }

  /// POST /api/auth/signup/caregiver  (multipart with optional CV)
  static Future<Map<String, dynamic>> signupCaregiver({
    required String name,
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
    required int age,
    required String nationalId,
    String? cvFilePath,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/auth/signup/caregiver'),
    );
    req.fields['name'] = name;
    req.fields['username'] = username;
    req.fields['email'] = email;
    req.fields['password'] = password;
    req.fields['confirm_password'] = confirmPassword;
    req.fields['age'] = age.toString();
    req.fields['national_id'] = nationalId;

    if (cvFilePath != null) {
      req.files.add(await http.MultipartFile.fromPath('cv', cvFilePath));
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    final data = json.decode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 201) return data;
    throw data['detail'] ?? 'Signup failed (${resp.statusCode})';
  }

  /// POST /api/auth/signup/relative
  static Future<Map<String, dynamic>> signupRelative({
    required String name,
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/auth/signup/relative'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'username': username,
        'email': email,
        'password': password,
        'confirm_password': confirmPassword,
      }),
    );
    final data = json.decode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 201) return data;
    throw data['detail'] ?? 'Signup failed (${resp.statusCode})';
  }

  // PATIENTS

  /// GET /api/patients?relative_id=<id>
  static Future<List<dynamic>> getPatientsForRelative(String relativeId) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/patients?relative_id=$relativeId'),
    );
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to fetch patients';
  }

  /// GET /api/caregivers/<caregiver_id>/patients
  static Future<List<dynamic>> getPatientsForCaregiver(
      String caregiverId) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/caregivers/$caregiverId/patients'),
    );
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to fetch patients';
  }

  /// POST /api/patients  body: {relative_id, name, date_of_birth, gender, current_medication}
  static Future<Map<String, dynamic>> createPatient({
    required String relativeId,
    required String name,
    String? dateOfBirth,
    String? gender,
    String? currentMedication,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/patients'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'relative_id': relativeId,
        'name': name,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (currentMedication != null) 'current_medication': currentMedication,
      }),
    );
    final data = json.decode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 201) return data;
    throw data['detail'] ?? 'Failed to create patient';
  }

  // CAREGIVERS

  /// GET /api/caregivers/available
  static Future<List<dynamic>> getAvailableCaregivers() async {
    final resp = await http.get(Uri.parse('$_baseUrl/caregivers/available'));
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to fetch caregivers';
  }

  /// POST /api/patients/<patient_id>/caregiver-offer  body: {requester_id, caregiver_id}
  static Future<Map<String, dynamic>> sendCaregiverOffer({
    required String patientId,
    required String requesterId,
    required String caregiverId,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/patients/$patientId/caregiver-offer'),
      headers: {'Content-Type': 'application/json'},
      body: json
          .encode({'requester_id': requesterId, 'caregiver_id': caregiverId}),
    );
    final data = json.decode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 201) return data;
    throw data['detail'] ?? 'Failed to send offer';
  }

  // CONTRACTS

  /// GET /api/caregivers/<caregiver_id>/contracts?status=PENDING
  static Future<List<dynamic>> getCaregiverContracts({
    required String caregiverId,
    String? status,
  }) async {
    var url = '$_baseUrl/caregivers/$caregiverId/contracts';
    if (status != null) url += '?status=$status';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to fetch contracts';
  }

  /// PATCH /api/contracts/<contract_id>/respond  body: {caregiver_id, action: "ACCEPT"}
  static Future<void> acceptContract({
    required String contractId,
    required String caregiverId,
  }) async {
    final resp = await http.patch(
      Uri.parse('$_baseUrl/contracts/$contractId/respond'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'caregiver_id': caregiverId, 'action': 'ACCEPT'}),
    );
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to accept contract';
  }

  /// PATCH /api/contracts/<contract_id>/respond  body: {caregiver_id, action: "DECLINE"}
  static Future<void> declineContract({
    required String contractId,
    required String caregiverId,
  }) async {
    final resp = await http.patch(
      Uri.parse('$_baseUrl/contracts/$contractId/respond'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'caregiver_id': caregiverId, 'action': 'DECLINE'}),
    );
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to decline contract';
  }

  /// POST /api/contracts/<contract_id>/end  body: {user_id}
  static Future<void> endContract({
    required String contractId,
    required String userId,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/contracts/$contractId/end'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId}),
    );
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Failed to end contract';
  }

  /// GET /api/patients/<patient_id>/caregiver
  static Future<Map<String, dynamic>?> getPatientCaregiver(
      String patientId) async {
    final resp =
        await http.get(Uri.parse('$_baseUrl/patients/$patientId/caregiver'));
    if (resp.statusCode == 200) {
      final body = resp.body;
      if (body == 'null' || body.isEmpty) return null;
      final data = json.decode(body);
      if (data == null) return null;
      return data as Map<String, dynamic>;
    }
    return null;
  }

  // RELATIVES

  /// GET /api/patients/<patient_id>/relatives
  static Future<List<dynamic>> getRelativesForPatient(String patientId) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/patients/$patientId/relatives'),
    );
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to fetch relatives';
  }

  /// POST /api/patients/<patient_id>/relatives  body: {requester_id, username, role_type}
  static Future<void> addRelative({
    required String patientId,
    required String requesterId,
    required String username,
    required String roleType,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/patients/$patientId/relatives'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'requester_id': requesterId,
        'username': username,
        'role_type': roleType,
      }),
    );
    if (resp.statusCode == 201) return;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Failed to add relative';
  }

  /// DELETE /api/patients/<patient_id>/relatives?requester_id=...&username=...
  static Future<void> removeRelative({
    required String patientId,
    required String requesterId,
    required String username,
  }) async {
    final resp = await http.delete(
      Uri.parse(
          '$_baseUrl/patients/$patientId/relatives?requester_id=$requesterId&username=$username'),
    );
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to remove relative';
  }

  // ALERTS

  /// GET /api/alerts?recipient_id=<id>&status=NEW
  static Future<List<dynamic>> getAlerts({
    required String recipientId,
    String? statusFilter,
  }) async {
    var url = '$_baseUrl/alerts?recipient_id=$recipientId';
    if (statusFilter != null) url += '&status=$statusFilter';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    return [];
  }

  /// PATCH /api/alerts/<alert_id>  body: {status: "SEEN"}
  static Future<void> acknowledgeAlert(String alertId) async {
    await http.patch(
      Uri.parse('$_baseUrl/alerts/$alertId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'status': 'SEEN'}),
    );
  }

  // MEDICATION

  /// GET /api/patients/<patient_id>/medication
  static Future<Map<String, dynamic>?> getMedicationSchedule(
      String patientId) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/patients/$patientId/medication'),
    );
    if (resp.statusCode == 200)
      return json.decode(resp.body) as Map<String, dynamic>;
    return null;
  }

  // ACTIVITY HISTORY

  /// GET /api/activity-recognition/history?patient_id=...&minutes=...
  static Future<List<dynamic>> getActivityHistory({
    required String patientId,
    int minutes = 1440,
  }) async {
    final resp = await http.get(
      Uri.parse(
          '$_baseUrl/activity-recognition/history?patient_id=$patientId&minutes=$minutes'),
    );
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      return data['events'] as List? ?? [];
    }
    return [];
  }

  // ADMIN

  /// GET /api/admin/users?role=CAREGIVER|RELATIVE|ADMIN
  static Future<List<dynamic>> adminListUsers({String? role}) async {
    var url = '$_baseUrl/admin/users';
    if (role != null) url += '?role=$role';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Failed to fetch users';
  }

  /// GET /api/admin/caregivers  (all caregivers including unverified)
  static Future<List<dynamic>> adminListCaregivers() async {
    final resp = await http.get(Uri.parse('$_baseUrl/admin/caregivers'));
    if (resp.statusCode == 200) return json.decode(resp.body) as List;
    throw (json.decode(resp.body) as Map)['detail'] ??
        'Failed to fetch caregivers';
  }

  /// PATCH /api/admin/caregivers/<caregiver_id>/salary  body: {admin_id, salary_per_hour}
  static Future<void> adminSetSalary({
    required String adminId,
    required String caregiverId,
    required double salaryPerHour,
  }) async {
    final resp = await http.patch(
      Uri.parse('$_baseUrl/admin/caregivers/$caregiverId/salary'),
      headers: {'Content-Type': 'application/json'},
      body:
          json.encode({'admin_id': adminId, 'salary_per_hour': salaryPerHour}),
    );
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Set salary failed';
  }

  /// DELETE /api/admin/users/<user_id>  body: {admin_id}
  static Future<void> adminDeleteUser({
    required String adminId,
    required String userId,
  }) async {
    final req =
        http.Request('DELETE', Uri.parse('$_baseUrl/admin/users/$userId'));
    req.headers['Content-Type'] = 'application/json';
    req.body = json.encode({'admin_id': adminId});
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Delete failed';
  }

  /// DELETE /api/admin/caregivers/<caregiver_id>/reject  body: {admin_id}
  static Future<void> adminRejectCaregiver({
    required String adminId,
    required String caregiverId,
  }) async {
    final req = http.Request(
        'DELETE', Uri.parse('$_baseUrl/admin/caregivers/$caregiverId/reject'));
    req.headers['Content-Type'] = 'application/json';
    req.body = json.encode({'admin_id': adminId});
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Reject failed';
  }

  /// PATCH /api/patients/<patient_id>/relatives/<relative_id>/role  body: {requester_id, role}
  static Future<void> updateRelativeRole({
    required String patientId,
    required String requesterId,
    required String relativeId,
    required String role,
  }) async {
    final resp = await http.patch(
      Uri.parse('$_baseUrl/patients/$patientId/relatives/$relativeId/role'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'requester_id': requesterId, 'role': role}),
    );
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Role change failed';
  }

  /// PATCH /api/admin/patients/<patient_id>/relatives/<relative_id>/role  body: {admin_id, role}
  static Future<void> adminChangeRelativeRole({
    required String adminId,
    required String patientId,
    required String relativeId,
    required String role,
  }) async {
    final resp = await http.patch(
      Uri.parse(
          '$_baseUrl/admin/patients/$patientId/relatives/$relativeId/role'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'admin_id': adminId, 'role': role}),
    );
    if (resp.statusCode == 200) return;
    throw (json.decode(resp.body) as Map)['detail'] ?? 'Role change failed';
  }

  // OBJECT DETECTION — POST /detect to port 5001

  static Future<void> detectObjects(Uint8List frameBytes) async {
    try {
      final req = http.MultipartRequest(
          'POST', Uri.parse('$_objectDetectionUrl/detect'));
      req.files.add(http.MultipartFile.fromBytes('frame', frameBytes,
          filename: 'frame.jpg'));
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        _handleDetectionResponse(resp.body);
      } else {
        AppState.detectedObjects.value = [];
      }
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
        AppState.alertStatus.value = AlertType.none;
      }
    } else if (AppState.alertStatus.value == AlertType.sharpObject) {
      AppState.alertStatus.value = AlertType.none;
    }
  }

  // FACE RECOGNITION — POST /analyze-face to port 5000

  static Future<void> analyzeFace(Uint8List frameBytes) async {
    try {
      final patientId = AppState.patientId.value ?? '1';
      final req =
          http.MultipartRequest('POST', Uri.parse('$_faceAiUrl/analyze-face'));
      req.files.add(http.MultipartFile.fromBytes('frame', frameBytes,
          filename: 'frame.jpg'));
      req.fields['patient_id'] = patientId;
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        _handleFaceResponse(resp.body);
      } else {
        AppState.detectedFaces.value = [];
      }
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
      left:
          location != null ? (location['left'] as num? ?? 0.3).toDouble() : 0.3,
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

  // ACTIVITY RECOGNITION — POST /process-frame to port 5003

  static Future<void> processActivityFrame(Uint8List frameBytes) async {
    try {
      final patientId = AppState.patientId.value;
      final req = http.MultipartRequest(
          'POST', Uri.parse('$_activityServerUrl/process-frame'));
      req.files.add(http.MultipartFile.fromBytes('frame', frameBytes,
          filename: 'frame.jpg'));
      if (patientId != null) {
        req.fields['patient_id'] = patientId;
      }
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        _handleActivityResponse(resp.body);
      } else {
        AppState.activityResult.value = ActivityResult.empty;
      }
    } catch (_) {
      AppState.activityResult.value = ActivityResult.empty;
    }
  }

  static void _handleActivityResponse(String responseText) {
    final data = json.decode(responseText) as Map<String, dynamic>;

    final activity = data['activity'] as String?;
    final confidence = (data['confidence'] as num? ?? 0.0).toDouble();
    final fallAlert = data['fall_alert'] as bool? ?? false;
    final wandering = data['wandering'] as bool? ?? false;
    final bufferProgress = (data['buffer_progress'] as num? ?? 0).toInt();
    final bufferTarget = (data['buffer_target'] as num? ?? 64).toInt();

    // Person bounding boxes (for AR overlay)
    final rawPersons = data['person_boxes'] as List<dynamic>? ?? [];
    final personBoxes = <DetectedObject>[];
    for (final raw in rawPersons) {
      final m = raw as Map<String, dynamic>;
      personBoxes.add(DetectedObject(
        label: 'person',
        confidence: (m['confidence'] as num? ?? 0.0).toDouble(),
        top: (m['y1'] as num? ?? 0.0).toDouble(),
        left: (m['x1'] as num? ?? 0.0).toDouble(),
        bottom: (m['y2'] as num? ?? 1.0).toDouble(),
        right: (m['x2'] as num? ?? 1.0).toDouble(),
      ));
    }

    // Dangerous objects: route into existing detectedObjects channel
    final rawDangerous = data['dangerous_objects'] as List<dynamic>? ?? [];
    final dangerousObjects = <DetectedObject>[];
    bool hasHighDanger = false;
    for (final raw in rawDangerous) {
      final m = raw as Map<String, dynamic>;
      final label = (m['label'] as String? ?? 'unknown').toLowerCase();
      final conf = (m['confidence'] as num? ?? 0.0).toDouble();
      final box = m['box'] as Map<String, dynamic>?;
      dangerousObjects.add(DetectedObject(
        label: label,
        confidence: conf,
        top: box != null ? (box['y1'] as num? ?? 0.0).toDouble() : 0.0,
        left: box != null ? (box['x1'] as num? ?? 0.0).toDouble() : 0.0,
        bottom: box != null ? (box['y2'] as num? ?? 1.0).toDouble() : 1.0,
        right: box != null ? (box['x2'] as num? ?? 1.0).toDouble() : 1.0,
      ));
      final danger = (m['danger_level'] as String? ?? 'LOW').toUpperCase();
      if (danger == 'HIGH' || danger == 'MEDIUM') hasHighDanger = true;
    }

    AppState.activityResult.value = ActivityResult(
      activity: activity,
      confidence: confidence,
      fallAlert: fallAlert,
      wandering: wandering,
      bufferProgress: bufferProgress,
      bufferTarget: bufferTarget,
      personBoxes: personBoxes,
    );
    AppState.detectedObjects.value = dangerousObjects;

    // Update top-level alert status (FALL takes priority)
    if (fallAlert) {
      if (AppState.alertStatus.value != AlertType.fall) {
        AppState.logAlert(AlertType.fall);
      }
      AppState.alertStatus.value = AlertType.fall;
    } else if (wandering) {
      if (AppState.alertStatus.value != AlertType.wandering) {
        AppState.logAlert(AlertType.wandering);
      }
      AppState.alertStatus.value = AlertType.wandering;
    } else if (hasHighDanger) {
      if (AppState.alertStatus.value != AlertType.sharpObject) {
        AppState.logAlert(AlertType.sharpObject);
      }
      AppState.alertStatus.value = AlertType.sharpObject;
    } else if (AppState.alertStatus.value == AlertType.fall ||
        AppState.alertStatus.value == AlertType.wandering ||
        AppState.alertStatus.value == AlertType.sharpObject) {
      AppState.alertStatus.value = AlertType.none;
    }
  }

  // SIMULATION HELPERS

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
