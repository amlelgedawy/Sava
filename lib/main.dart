import 'package:flutter/material.dart';
import 'screens/main_wrapper.dart';
import 'services/database_service.dart';
import 'services/live_sensor_service.dart';
import 'theme.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Start Sensor Logic
    LiveSensorService.startHardwareStream();

    // Load Initial Data
    DatabaseService.refreshDashboardFromDatabase();

    runApp(const SavaApp());
  } catch (e) {
    debugPrint("CRITICAL INIT ERROR: $e");
    // Fallback run to avoid white screen
    runApp(const SavaApp());
  }
}

class SavaApp extends StatelessWidget {
  const SavaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SAVA Care',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: SovaColors.bg,
        textTheme: SovaTheme.textTheme,
      ),
      home: const MainWrapper(),
    );
  }
}
