import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/patient_models.dart';
import '../app_state.dart';
import 'api_service.dart';

class DatabaseService {
  static const String _baseUrl = "http://192.168.1.3:8000/api";
  //static const String _baseUrl = "http://10.0.2.2:8000/api"; // Android emulator alias

  static Timer? _alertPollingTimer;
  static Timer? _heartRateTimer;
  static Timer? _activityTimer;
  static int _heartRateIndex = 0;
  static const List<int> _heartRateSequence = [
    68, 71, 74, 72, 76, 73, 70, 75, 72, 69, 74, 77, 73, 71, 75
  ];

  // Alert spam prevention — track which backend IDs we've already notified
  static final Set<String> _seenAlertIds = {};

  // --- KEEPING ALL LOCAL DATA FOR YOUR OTHER PAGES ---
  static final List<Medication> _meds = [];
  static final List<ActivityLog> _logs = [];

  // SIGNUP LOGIC

  static Future<void> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    AppState.isAuthLoading.value = true;
    AppState.authError.value = null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/signup/caregiver'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'email': email,
          'password': password,
          'role': 'CAREGIVER',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        AppState.caregiverId.value = data['id'].toString();
        AppState.caregiverName.value = data['name'];
        await _fetchLinkedPatient();
        _startAlertPolling();
        refreshDashboard();
        AppState.isLoggedIn.value = true;
      } else {
        final data = json.decode(response.body);
        AppState.authError.value =
            data['detail'] ?? "Signup failed (${response.statusCode})";
      }
    } catch (e) {
      AppState.authError.value =
          "Signup Error: ${e.runtimeType} — ${e.toString()}";
    } finally {
      AppState.isAuthLoading.value = false;
    }
  }

  // LOGIN LOGIC

  static Future<void> login({
    required String email,
    required String password,
  }) async {
    AppState.isAuthLoading.value = true;
    AppState.authError.value = null;

    try {
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/auth/login'), // no trailing slash — matches Django url
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final id = data['id'].toString();
        AppState.userId.value = id;
        AppState.caregiverId.value = id;
        AppState.caregiverName.value = data['name'];
        await _fetchLinkedPatient();
        _startAlertPolling();
        refreshDashboard();
        AppState.isLoggedIn.value = true;
      } else {
        final data = json.decode(response.body);
        AppState.authError.value =
            data['detail'] ?? "Login failed (${response.statusCode})";
      }
    } catch (e) {
      AppState.authError.value =
          "Login Error: ${e.runtimeType} — ${e.toString()}";
    } finally {
      AppState.isAuthLoading.value = false;
    }
  }

  // PRESERVED METHODS (Do not change - used by other pages)

  static Future<void> _fetchLinkedPatient() async {
    final caregiverId = AppState.caregiverId.value;
    if (caregiverId == null) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregivers/$caregiverId/patients'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> patients = json.decode(response.body);
        if (patients.isNotEmpty) {
          AppState.patientId.value = patients[0]['id'].toString();
          AppState.patientName.value = patients[0]['name'];
        }
      }
    } catch (_) {}
  }

  static void startAlertPollingForUser(String userId) {
    _alertPollingTimer?.cancel();
    _activityTimer?.cancel();
    _fetchNewAlerts();
    fetchActivityHistory();
    _alertPollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchNewAlerts(),
    );
    _activityTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => fetchActivityHistory(),
    );
    _startHeartRateSimulation();
  }

  static void _startAlertPolling() {
    startAlertPollingForUser(AppState.caregiverId.value ?? '');
  }

  static void stopAlertPolling() {
    _alertPollingTimer?.cancel();
    _alertPollingTimer = null;
    _heartRateTimer?.cancel();
    _heartRateTimer = null;
    _activityTimer?.cancel();
    _activityTimer = null;
    _seenAlertIds.clear();
  }

  static void _startHeartRateSimulation() {
    _heartRateTimer?.cancel();
    _heartRateIndex = 0;
    AppState.heartRate.value = _heartRateSequence[0];
    _heartRateTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _heartRateIndex = (_heartRateIndex + 1) % _heartRateSequence.length;
      AppState.heartRate.value = _heartRateSequence[_heartRateIndex];
    });
  }

  static Future<void> _fetchNewAlerts() async {
    final uid = AppState.userId.value ?? AppState.caregiverId.value;
    if (uid == null || !AppState.isLoggedIn.value) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/alerts?recipient_id=$uid&status=NEW'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> alerts = json.decode(response.body);
        if (alerts.isEmpty) {
          AppState.alertStatus.value = AlertType.none;
          return;
        }

        // Find the latest alert we haven't seen yet
        Map<String, dynamic>? unseenAlert;
        for (final a in alerts) {
          final id = (a['id'] ?? a['_id'] ?? '').toString();
          if (id.isEmpty || !_seenAlertIds.contains(id)) {
            unseenAlert = a as Map<String, dynamic>;
            if (id.isNotEmpty) {
              _seenAlertIds.add(id);
              ApiService.markAlertSeen(id);
            }
            break;
          }
        }

        // Derive current status from the most recent alert regardless of seen state
        final String type =
            (alerts[0]['alert_type'] as String? ?? '').toUpperCase();
        AlertType newType;
        switch (type) {
          case 'FALL':
          case 'FALL_DETECTED':
            newType = AlertType.fall;
            break;
          case 'OBJECT':
          case 'DANGEROUS_OBJECT':
            newType = AlertType.sharpObject;
            break;
          case 'FACE':
            newType = AlertType.unknown_face;
            break;
          case 'WANDERING':
            newType = AlertType.wandering;
            break;
          case 'BATHROOM':
            newType = AlertType.bathroomTimeout;
            break;
          default:
            newType = AlertType.none;
        }

        // Only push to alert history for newly seen alerts
        if (unseenAlert != null && newType != AlertType.none) {
          AppState.logAlert(newType);
        }
        AppState.alertStatus.value = newType;
      }
    } catch (_) {}
  }

  static void refreshDashboard() {
    fetchMedicationSchedule();
    AppState.allActivityLogs.value = List.from(_logs);
    AppState.lastActivity.value = _logs.isEmpty ? null : _logs.last;
  }

  static Future<void> fetchMedicationSchedule() async {
    final patientId = AppState.patientId.value;
    if (patientId == null || patientId.isEmpty) return;
    try {
      final data = await ApiService.getMedicationSchedule(patientId);
      final rawEntries = (data?['entries'] as List<dynamic>?) ?? [];
      _meds.clear();
      for (final e in rawEntries) {
        _meds.add(Medication(
          name: e['medicine_name'] as String? ?? '',
          time: e['time_to_consume'] as String? ?? '',
          dosage: e['dosage'] as String? ?? '',
          notes: e['notes'] as String? ?? '',
        ));
      }
    } catch (_) {}
    AppState.allMedications.value = List.from(_meds);
    final now = DateTime.now();
    final nowMin = (now.hour * 60) + now.minute;
    try {
      AppState.nextMedication.value = _meds.firstWhere(
        (m) => !m.isTaken && _timeToMin(m.time) > nowMin,
      );
    } catch (_) {
      AppState.nextMedication.value = _meds.isNotEmpty ? _meds.first : null;
    }
  }

  static Future<void> fetchActivityHistory() async {
    final patientId = AppState.patientId.value;
    if (patientId == null) return;
    try {
      final events = await ApiService.getActivityHistory(patientId: patientId);
      _logs.clear();
      for (final e in events) {
        final payload = e['payload'] as Map<String, dynamic>? ?? {};
        final activity =
            (payload['activity'] as String? ?? e['event_type'] as String? ?? '')
                .toUpperCase();
        final createdAt = e['created_at'];
        String timeStr = '';
        if (createdAt != null) {
          try {
            final dt = DateTime.parse(createdAt.toString()).toLocal();
            timeStr = DateFormat.jm().format(dt);
          } catch (_) {}
        }
        _logs.add(ActivityLog(
          title: _activityLabel(activity),
          finishTime: timeStr,
          icon: _activityIcon(activity),
          isFinished: true,
        ));
      }
      refreshDashboard();
    } catch (_) {}
  }

  static String _activityLabel(String activity) {
    switch (activity) {
      case 'EAT':
        return 'Eating';
      case 'DRINK':
        return 'Drinking';
      case 'SLEEP':
        return 'Sleeping';
      case 'FALL':
        return 'Fall Detected';
      case 'WALK':
        return 'Walking';
      case 'SIT':
        return 'Sitting';
      case 'STAND':
        return 'Standing';
      case 'USE_PHONE':
        return 'Using Phone';
      case 'CHEST_PAIN':
        return 'Chest Pain';
      case 'TYPE_FALL':
        return 'Fall Detected';
      case 'TYPE_ACTIVITY':
        return 'Activity';
      default:
        return activity.isNotEmpty
            ? activity[0].toUpperCase() + activity.substring(1).toLowerCase()
            : 'Activity';
    }
  }

  static IconData _activityIcon(String activity) {
    switch (activity) {
      case 'EAT':
        return Icons.restaurant_rounded;
      case 'DRINK':
        return Icons.local_drink_rounded;
      case 'SLEEP':
        return Icons.bedtime_rounded;
      case 'FALL':
        return Icons.emergency_rounded;
      case 'WALK':
        return Icons.directions_walk_rounded;
      case 'SIT':
        return Icons.chair_rounded;
      case 'STAND':
        return Icons.accessibility_new_rounded;
      case 'USE_PHONE':
        return Icons.phone_android_rounded;
      case 'CHEST_PAIN':
        return Icons.favorite_rounded;
      case 'TYPE_FALL':
        return Icons.emergency_rounded;
      default:
        return Icons.fiber_manual_record_rounded;
    }
  }

  static void addNewActivity(String title, IconData icon) {
    final timeStr = DateFormat.jm().format(DateTime.now());
    _logs.add(
      ActivityLog(
        title: title,
        finishTime: timeStr,
        icon: icon,
        isFinished: true,
      ),
    );
    refreshDashboard();
  }

  static void markAsTaken(Medication med) {
    med.isTaken = true;
    refreshDashboard();
  }

  static int _timeToMin(String s) {
    final f = DateFormat.jm().parse(s);
    return (f.hour * 60) + f.minute;
  }

  static Color getActivityColor(String title) {
    switch (title.toLowerCase()) {
      case 'sleeping':
      case 'sleep':
        return const Color(0xFF1A2E44);
      case 'eating':
      case 'eat':
        return const Color(0xFFFF9F67);
      case 'drinking':
      case 'drink':
        return const Color(0xFF48CAE4);
      case 'woke up':
        return const Color(0xFFFFD166);
      case 'walking':
      case 'walk':
        return const Color(0xFF4CAF50);
      case 'sitting':
      case 'sit':
        return const Color(0xFF9C8060);
      case 'standing':
      case 'stand':
        return const Color(0xFF607D8B);
      case 'using phone':
      case 'use_phone':
        return const Color(0xFF7B1FA2);
      case 'fall detected':
      case 'fall':
      case 'type_fall':
        return const Color(0xFFD32F2F);
      case 'chest pain':
      case 'chest_pain':
        return const Color(0xFFE53935);
      default:
        return const Color(0xFF8DA399);
    }
  }
}
