import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../app_state.dart';
import '../services/database_service.dart';
import 'signup_page.dart';
import 'main_wrapper.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;

  @override
  void initState() {
    super.initState();
    AppState.isLoggedIn.addListener(_onLoginSuccess);
    AppState.authError.addListener(_onAuthError);
  }

  @override
  void dispose() {
    AppState.isLoggedIn.removeListener(_onLoginSuccess);
    AppState.authError.removeListener(_onAuthError);
    super.dispose();
  }

  void _onLoginSuccess() {
    if (AppState.isLoggedIn.value && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainWrapper()),
      );
    }
  }

  void _onAuthError() {
    if (AppState.authError.value != null && mounted) {
      setState(() => _emailError = AppState.authError.value);
    }
  }

  void _login() {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty)
      return;
    DatabaseService.login(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Text(
                "SAVA",
                style: SovaTheme.textTheme.labelMedium,
              ).animate().fadeIn(),
              const SizedBox(height: 8),
              Text(
                "Welcome Back",
                style: SovaTheme.textTheme.displayMedium,
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 48),
              _buildField(_emailController, "Email", Icons.email_outlined),
              const SizedBox(height: 16),
              _buildField(
                _passwordController,
                "Password",
                Icons.lock_outline,
                obscure: true,
              ),
              if (_emailError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _emailError!,
                    style: const TextStyle(color: SovaColors.danger),
                  ),
                ),
              const SizedBox(height: 32),
              ValueListenableBuilder<bool>(
                valueListenable: AppState.isAuthLoading,
                builder: (context, loading, _) => GestureDetector(
                  onTap: loading ? null : _login,
                  child: Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      color: SovaColors.charcoal,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Center(
                      child: loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Login",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupPage()),
                  ),
                  child: const Text(
                    "Create account",
                    style: TextStyle(color: SovaColors.sage),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
        ),
      ),
    );
  }
}
