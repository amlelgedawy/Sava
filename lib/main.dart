import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/login_page.dart';
import 'services/database_service.dart';
import 'theme.dart';

List<CameraDescription> cameras = [];

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();
    DatabaseService.refreshDashboard();
    runApp(const SavaApp());
  } catch (e) {
    runApp(const SavaApp());
  }
}

class SavaApp extends StatelessWidget {
  const SavaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SAVA',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF9FBF9),
        textTheme: SovaTheme.textTheme,
      ),
      home: const LoginPage(),
    );
  }
}
