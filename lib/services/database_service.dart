import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/patient_models.dart';
import '../app_state.dart';

class DatabaseService {
  static const String _baseUrl = "http://localhost:8000/api";

  static Timer? _alertPollingTimer;

  // --- KEEPING ALL LOCAL DATA FOR YOUR OTHER PAGES ---
  static final List<Medication> _meds = [
    Medication(name: "Vitamin D", time: "08:00 AM"),
    Medication(name: "Donepezil", time: "12:00 PM"),
    Medication(name: "Quetiapine", time: "09:00 PM"),
  ];

  static final List<ActivityLog> _logs = [
    ActivityLog(
      title: "Woke Up",
      finishTime: "07:30 AM",
      icon: Icons.wb_sunny_rounded,
      isFinished: true,
    ),
    ActivityLog(
      title: "Eating",
      finishTime: "04:00 PM",
      icon: Icons.restaurant_rounded,
      isFinished: true,
    ),
  ];

  // ==========================================================
  // SIGNUP LOGIC
  // ==========================================================
  static Future<void> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    AppState.isAuthLoading.value = true;
    AppState.authError.value = null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/users'), // no trailing slash — matches Django url
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

  // ==========================================================
  // LOGIN LOGIC
  // ==========================================================
  static Future<void> login({
    required String email,
    required String password,
  }) async {
    AppState.isAuthLoading.value = true;
    AppState.authError.value = null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/login'), // no trailing slash — matches Django url
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
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
            data['detail'] ?? "Login failed (${response.statusCode})";
      }
    } catch (e) {
      AppState.authError.value =
          "Login Error: ${e.runtimeType} — ${e.toString()}";
    } finally {
      AppState.isAuthLoading.value = false;
    }
  }

  // ==========================================================
  // PRESERVED METHODS (Do not change - used by other pages)
  // ==========================================================
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

  static void _startAlertPolling() {
    _alertPollingTimer?.cancel();
    _fetchNewAlerts();
    _alertPollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchNewAlerts(),
    );
  }

  static void stopAlertPolling() {
    _alertPollingTimer?.cancel();
    _alertPollingTimer = null;
  }

  static Future<void> _fetchNewAlerts() async {
    final caregiverId = AppState.caregiverId.value;
    if (caregiverId == null || !AppState.isLoggedIn.value) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/alerts?caregiver_id=$caregiverId&status=NEW'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> alerts = json.decode(response.body);
        if (alerts.isEmpty) {
          AppState.alertStatus.value = AlertType.none;
          return;
        }
        final String type = alerts[0]['alert_type'].toString().toUpperCase();
        switch (type) {
          case 'FALL':
            AppState.alertStatus.value = AlertType.fall;
            break;
          case 'OBJECT':
            AppState.alertStatus.value = AlertType.sharpObject;
            break;
          case 'FACE':
            AppState.alertStatus.value = AlertType.unknown_face;
            break;
          case 'WANDERING':
            AppState.alertStatus.value = AlertType.wandering;
            break;
          case 'BATHROOM':
            AppState.alertStatus.value = AlertType.bathroomTimeout;
            break;
          default:
            AppState.alertStatus.value = AlertType.none;
        }
      }
    } catch (_) {}
  }

  static void refreshDashboard() {
    AppState.allMedications.value = List.from(_meds);
    AppState.allActivityLogs.value = List.from(_logs);
    final now = DateTime.now();
    final nowMin = (now.hour * 60) + now.minute;
    try {
      AppState.nextMedication.value = _meds.firstWhere(
        (m) => !m.isTaken && _timeToMin(m.time) > nowMin,
      );
    } catch (_) {
      AppState.nextMedication.value = _meds.isNotEmpty ? _meds.first : null;
    }
    AppState.lastActivity.value = _logs.isEmpty ? null : _logs.last;
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
        return const Color(0xFF1A2E44);
      case 'eating':
        return const Color(0xFFFF9F67);
      case 'drinking':
        return const Color(0xFF48CAE4);
      case 'woke up':
        return const Color(0xFFFFD166);
      default:
        return const Color(0xFF8DA399);
    }
  }
}
