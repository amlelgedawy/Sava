import 'package:flutter/material.dart';

class Medication {
  final String name;
  final String time;
  bool isTaken;
  Medication({required this.name, required this.time, this.isTaken = false});
}

class ActivityLog {
  String title;
  String finishTime;
  IconData icon;
  bool isFinished;

  ActivityLog({
    required this.title,
    required this.finishTime,
    required this.icon,
    required this.isFinished,
  });
}
