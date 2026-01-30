import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/patient_models.dart';
import '../app_state.dart';

class DatabaseService {
  static const String caregiverName = "Sarah";
  static const String patientName = "Robert Sava";

  static final List<Medication> _meds = [
    Medication(name: "Vitamin D", time: "08:00 AM"),
    Medication(name: "Donepezil", time: "12:00 PM"),
    Medication(name: "Quetiapine", time: "09:00 PM"),
  ];

  static final List<ActivityLog> _history = [
    ActivityLog(
      title: "Woke Up",
      finishTime: "07:30 AM",
      icon: Icons.wb_sunny_rounded,
      isFinished: true,
    ),
    ActivityLog(
      title: "Drinking",
      finishTime: "10:15 AM",
      icon: Icons.water_drop_rounded,
      isFinished: true,
    ),
    ActivityLog(
      title: "Eating",
      finishTime: "04:00 PM",
      icon: Icons.restaurant_rounded,
      isFinished: true,
    ),
  ];

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

  static void markAsTaken(Medication med) {
    med.isTaken = true;
    refreshDashboardFromDatabase();
  }

  static void addRandomActivitySimulation() {
    final List<Map<String, dynamic>> options = [
      {'t': 'Eating', 'i': Icons.restaurant_rounded},
      {'t': 'Drinking', 'i': Icons.water_drop_rounded},
      {'t': 'Sleeping', 'i': Icons.bedtime_rounded},
    ];
    final random = options[Random().nextInt(options.length)];
    final String nowTime = DateFormat.jm().format(DateTime.now());

    if (_history.isNotEmpty && !_history.last.isFinished) {
      _history.last.isFinished = true;
      _history.last.finishTime = nowTime;
    }
    final newLog = ActivityLog(
      title: random['t'],
      icon: random['i'],
      finishTime: nowTime,
      isFinished: false,
    );
    _history.add(newLog);
    refreshDashboardFromDatabase();
  }

  static void refreshDashboardFromDatabase() {
    final now = DateTime.now();
    final int nowMin = (now.hour * 60) + now.minute;

    _meds.sort((a, b) => _timeToMin(a.time).compareTo(_timeToMin(b.time)));
    Medication? next;
    for (var m in _meds) {
      if (!m.isTaken && _timeToMin(m.time) > nowMin) {
        next = m;
        break;
      }
    }
    AppState.nextMedication.value = next ?? _meds.first;
    AppState.allMedications.value = List.from(_meds);
    AppState.lastActivity.value = _history.last;
    AppState.allActivityLogs.value = List.from(_history);
  }

  static int _timeToMin(String s) {
    try {
      final f = DateFormat.jm().parse(s);
      return (f.hour * 60) + f.minute;
    } catch (e) {
      return 0;
    }
  }
}
