import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../models/user_models.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../relative/relative_wrapper.dart';

class RelativeSignupPage extends StatefulWidget {
  const RelativeSignupPage({super.key});
  @override
  State<RelativeSignupPage> createState() => _RelativeSignupPageState();
}

class _RelativeSignupPageState extends State<RelativeSignupPage> {
  final _pageController = PageController();
  int _step = 0;
  bool _loading = false;

  // Step 0 – Basic Info
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _passVisible = false;
  String? _error0;

  // Step 1 – Your Face Video
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _myVideoRecorded = false;
  bool _myRecording = false;
  int _myCountdown = 13;
  String _aiUrl = "http://10.0.2.2:5000";
  XFile? _recordedVideo;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && !_validateStep0()) return;
    if (_step == 1) {
      if (!_myVideoRecorded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please record your face video first')),
        );
        return;
      }
      _submit();
      return;
    }
    setState(() => _step++);
    _pageController.animateToPage(_step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    if (_step == 1) {
      _stopCamera();
    }
    setState(() => _step--);
    _pageController.animateToPage(_step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  bool _validateStep0() {
    if ([_nameCtrl, _usernameCtrl, _emailCtrl, _passCtrl, _confirmCtrl]
        .any((c) => c.text.isEmpty)) {
      setState(() => _error0 = 'Please fill all fields');
      return false;
    }
    if (!_emailCtrl.text.contains('@')) {
      setState(() => _error0 = 'Enter a valid email');
      return false;
    }
    if (_passCtrl.text.length < 8) {
      setState(() => _error0 = 'Password must be at least 8 characters');
      return false;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error0 = 'Passwords do not match');
      return false;
    }
    setState(() => _error0 = null);
    return true;
  }

  Future<void> _startCamera() async {
    if (cameras.isEmpty) return;
    try {
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
    } catch (_) {
      setState(() => _cameraReady = false);
    }
  }

  void _stopCamera() {
    _cameraController?.dispose();
    _cameraController = null;
  }

  Future<void> _startMyRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _myRecording = true;
        _myCountdown = 13;
      });
      for (int i = 13; i >= 0; i--) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() => _myCountdown = i);
      }
      _recordedVideo = await _cameraController!.stopVideoRecording();
      if (!mounted) return;
      setState(() {
        _myRecording = false;
        _myVideoRecorded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myRecording = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final userData = await ApiService.signupRelative(
        name: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        confirmPassword: _confirmCtrl.text,
      );
      final id = userData['id'].toString();
      AppState.userId.value = id;
      AppState.userRole.value = UserRole.relative;
      AppState.caregiverName.value = userData['name'] as String? ?? '';

      // Upload face video to AI server
      if (_recordedVideo != null) {
        final bytes = await _recordedVideo!.readAsBytes();
        final name = _nameCtrl.text.trim().toLowerCase();
        final req =
            http.MultipartRequest('POST', Uri.parse('$_aiUrl/enroll-relative'));
        req.files.add(http.MultipartFile.fromBytes('video', bytes,
            filename: 'recording.mp4'));
        req.fields['person_name'] = name;
        await req.send();
      }

      DatabaseService.startAlertPollingForUser(id);
      DatabaseService.refreshDashboard();
      AppState.isLoggedIn.value = true;
    } catch (e) {
      if (mounted) setState(() => _error0 = e.toString());
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = false;
      _step = 2;
    });
    _pageController.animateToPage(2,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _step < 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    color: SovaColors.charcoal, size: 20),
                onPressed: _back,
              )
            : null,
      ),
      body: Column(
        children: [
          if (_step < 2) _stepBar(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep0(),
                _buildStep1(),
                _buildDone(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Row(
        children: List.generate(2, (i) {
          final done = i < _step;
          final active = i == _step;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 4,
              decoration: BoxDecoration(
                color: done
                    ? SovaColors.success
                    : active
                        ? SovaColors.coral
                        : SovaColors.sensorNeutral,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Step 0: Basic Info ───────────────────────────────────────────────────

  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RELATIVE', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Basic Information', style: SovaTheme.textTheme.displayMedium),
          Text('Step 1 of 2',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 32),
          _field(_nameCtrl, 'Full Name', Icons.person_outline),
          const SizedBox(height: 16),
          _field(_usernameCtrl, 'Username', Icons.alternate_email),
          const SizedBox(height: 16),
          _field(_emailCtrl, 'Email', Icons.email_outlined,
              type: TextInputType.emailAddress),
          const SizedBox(height: 16),
          _field(_passCtrl, 'Password', Icons.lock_outline,
              obscure: !_passVisible,
              suffix: IconButton(
                icon: Icon(
                    _passVisible ? Icons.visibility_off : Icons.visibility,
                    color: SovaColors.sage),
                onPressed: () => setState(() => _passVisible = !_passVisible),
              )),
          const SizedBox(height: 16),
          _field(_confirmCtrl, 'Confirm Password', Icons.lock_outline,
              obscure: true),
          if (_error0 != null) _errorText(_error0!),
          const SizedBox(height: 32),
          _primaryBtn('Continue', _next),
        ],
      ),
    );
  }

  // ── Step 1: Your Face Video ──────────────────────────────────────────────

  Widget _buildStep1() {
    // Start camera when entering step 1
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cameraController == null) _startCamera();
    });

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RELATIVE', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Your Face Video', style: SovaTheme.textTheme.displayMedium),
          Text('Step 2 of 2',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            'Record a 10–15 second video of your face for identity verification.',
            style: TextStyle(color: SovaColors.sage, height: 1.5),
          ),
          const Spacer(),
          Center(
            child: SizedBox(
              width: 280,
              height: 280,
              child: ClipOval(
                child: _cameraReady && _cameraController != null
                    ? CameraPreview(_cameraController!)
                    : const Center(
                        child:
                            CircularProgressIndicator(color: SovaColors.coral),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (!_myVideoRecorded)
            _primaryBtn('Start Recording (13s)', _startMyRecording,
                color: SovaColors.coral)
          else
            _primaryBtn(
                'Re-record', () => setState(() => _myVideoRecorded = false),
                color: SovaColors.navy),
          const Spacer(),
          _primaryBtn('Continue', _next,
              color: _myVideoRecorded
                  ? SovaColors.coral
                  : SovaColors.sensorNeutral),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Step 2: Done ─────────────────────────────────────────────────────────

  Widget _buildDone() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: SovaColors.coral.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.favorite, color: SovaColors.coral, size: 52),
            ).animate().scale(delay: 200.ms),
            const SizedBox(height: 32),
            Text('Welcome to SAVA!',
                style: SovaTheme.textTheme.displayMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'You are now the primary relative. You can assign a caregiver and manage your loved one\'s care.',
              style: TextStyle(color: SovaColors.sage, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            _primaryBtn('Enter App', () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const RelativeWrapper()),
                (_) => false,
              );
            }, color: SovaColors.coral),
          ],
        ).animate().fadeIn(delay: 100.ms),
      ),
    );
  }

  // ── Shared Widgets ───────────────────────────────────────────────────────

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

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(msg, style: const TextStyle(color: SovaColors.danger)),
      );

  Widget _primaryBtn(String label, VoidCallback? onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: color ?? SovaColors.charcoal,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
        ),
      ),
    );
  }
}
