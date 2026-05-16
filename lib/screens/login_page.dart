import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models/user_models.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import 'auth/landing_page.dart';
import 'caregiver/caregiver_wrapper.dart';
import 'relative/relative_wrapper.dart';
import 'admin/admin_wrapper.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _passVisible = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiService.login(email: email, password: password);

      if (!mounted) return;

      final id = data['id'].toString();
      final name = data['name'] as String? ?? '';
      final role = (data['role'] as String? ?? '').toUpperCase();

      AppState.userId.value = id;
      AppState.caregiverName.value = name;

      if (role == 'CAREGIVER') {
        AppState.userRole.value = UserRole.caregiver;
        AppState.caregiverId.value = id;
        final patients = await ApiService.getPatientsForCaregiver(id);
        if (patients.isNotEmpty) {
          AppState.patientId.value = patients[0]['id'].toString();
          AppState.patientName.value = patients[0]['name'] as String? ?? '';
        }
      } else if (role == 'RELATIVE') {
        AppState.userRole.value = UserRole.relative;
        final patients = await ApiService.getPatientsForRelative(id);
        if (patients.isNotEmpty) {
          AppState.patientId.value = patients[0]['id'].toString();
          AppState.patientName.value = patients[0]['name'] as String? ?? '';
        }
      } else if (role == 'ADMIN') {
        AppState.userRole.value = UserRole.admin;
      }

      DatabaseService.startAlertPollingForUser(id);
      DatabaseService.refreshDashboard();
      AppState.isLoggedIn.value = true;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = false);

    final role = AppState.userRole.value;
    Widget dest;
    if (role == UserRole.caregiver) {
      dest = const CaregiverWrapper();
    } else if (role == UserRole.relative) {
      dest = const RelativeWrapper();
    } else {
      dest = const AdminWrapper();
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => dest),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: SovaColors.charcoal, size: 20),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LandingPage()),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text('SAVA', style: SovaTheme.textTheme.labelMedium)
                  .animate()
                  .fadeIn(),
              const SizedBox(height: 8),
              Text('Welcome Back', style: SovaTheme.textTheme.displayMedium)
                  .animate()
                  .fadeIn(delay: 100.ms),
              const SizedBox(height: 8),
              Text(
                'Sign in to continue',
                style: TextStyle(color: SovaColors.sage, fontSize: 15),
              ).animate().fadeIn(delay: 180.ms),
              const SizedBox(height: 40),
              _field(_emailCtrl, 'Email', Icons.email_outlined,
                  type: TextInputType.emailAddress),
              const SizedBox(height: 16),
              _field(_passCtrl, 'Password', Icons.lock_outline,
                  obscure: !_passVisible,
                  suffix: IconButton(
                    icon: Icon(
                        _passVisible ? Icons.visibility_off : Icons.visibility,
                        color: SovaColors.sage),
                    onPressed: () =>
                        setState(() => _passVisible = !_passVisible),
                  )),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      style: const TextStyle(color: SovaColors.danger)),
                ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _loading ? null : _login,
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                      color: SovaColors.charcoal,
                      borderRadius: BorderRadius.circular(30)),
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Sign In',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: SovaColors.softGlass,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Demo Accounts',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: SovaColors.charcoal)),
                    const SizedBox(height: 8),
                    _demoRow('Caregiver', 'ahmed@sava.com', 'pass123'),
                    _demoRow('Relative', 'mohamed@sava.com', 'pass123'),
                    _demoRow('Admin', 'admin@sava.com', 'admin123'),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? type,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(28)),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: SovaColors.sage),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
        ),
      ),
    );
  }

  Widget _demoRow(String role, String email, String pass) {
    return GestureDetector(
      onTap: () {
        _emailCtrl.text = email;
        _passCtrl.text = pass;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text('$role: ',
              style: const TextStyle(color: SovaColors.sage, fontSize: 12)),
          Text(email,
              style: const TextStyle(
                  color: SovaColors.charcoal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(' / $pass',
              style: const TextStyle(color: SovaColors.sage, fontSize: 12)),
        ]),
      ),
    );
  }
}
