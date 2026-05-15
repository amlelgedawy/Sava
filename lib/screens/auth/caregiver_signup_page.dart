import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../models/user_models.dart';
import '../../services/mock_service.dart';
import '../caregiver/caregiver_wrapper.dart';

class CaregiverSignupPage extends StatefulWidget {
  const CaregiverSignupPage({super.key});
  @override
  State<CaregiverSignupPage> createState() => _CaregiverSignupPageState();
}

class _CaregiverSignupPageState extends State<CaregiverSignupPage> {
  final _pageController = PageController();
  int _step = 0;
  bool _loading = false;

  // Step 0 – Basic Info
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _passVisible = false;
  String? _error0;

  // Step 1 – Professional Info
  final _ageCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  String? _cvFile;
  String? _idPhotoFile;
  String? _error1;

  // Step 2 – Face Video
  bool _videoRecorded = false;
  bool _recording = false;
  int _countdown = 13;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _ageCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && !_validateStep0()) return;
    if (_step == 1 && !_validateStep1()) return;
    if (_step == 2) {
      if (!_videoRecorded) {
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
    setState(() => _step--);
    _pageController.animateToPage(_step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  bool _validateStep0() {
    if ([_nameCtrl, _emailCtrl, _passCtrl, _confirmCtrl]
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

  bool _validateStep1() {
    final age = int.tryParse(_ageCtrl.text);
    if (age == null || age < 18) {
      setState(() => _error1 = 'Enter a valid age (18+)');
      return false;
    }
    if (_idCtrl.text.length != 14) {
      setState(() => _error1 = 'National ID must be exactly 14 digits');
      return false;
    }
    setState(() => _error1 = null);
    return true;
  }

  Future<void> _startRecording() async {
    setState(() {
      _recording = true;
      _countdown = 13;
    });
    for (int i = 13; i >= 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _countdown = i);
    }
    setState(() {
      _recording = false;
      _videoRecorded = true;
    });
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final user = await MockService.instance.signupCaregiver(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      age: int.parse(_ageCtrl.text),
      nationalId: _idCtrl.text,
      cvFileName: _cvFile,
      nationalIdPhotoName: _idPhotoFile,
    );
    AppState.currentUser.value = user;
    AppState.userRole.value = UserRole.caregiver;
    AppState.caregiverName.value = user.name;
    AppState.caregiverId.value = user.id;
    AppState.isLoggedIn.value = true;
    setState(() {
      _loading = false;
      _step = 3;
    });
    _pageController.animateToPage(3,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _step < 3
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    color: SovaColors.charcoal, size: 20),
                onPressed: _back,
              )
            : null,
      ),
      body: Column(
        children: [
          if (_step < 3) _stepBar(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep0(),
                _buildStep1(),
                _buildStep2(),
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
        children: List.generate(3, (i) {
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
                        ? SovaColors.navy
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
          Text('CAREGIVER', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Basic Information', style: SovaTheme.textTheme.displayMedium),
          Text('Step 1 of 3',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 32),
          _field(_nameCtrl, 'Full Name', Icons.person_outline),
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

  // ── Step 1: Professional Info ────────────────────────────────────────────

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CAREGIVER', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Professional Info', style: SovaTheme.textTheme.displayMedium),
          Text('Step 2 of 3',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 32),
          _field(_ageCtrl, 'Age', Icons.cake_outlined,
              type: TextInputType.number),
          const SizedBox(height: 16),
          _field(_idCtrl, 'National ID Number (14 digits)',
              Icons.credit_card_outlined,
              type: TextInputType.number),
          const SizedBox(height: 16),
          _uploadTile(
            label: 'National ID Photo',
            icon: Icons.credit_card,
            file: _idPhotoFile,
            onTap: () =>
                setState(() => _idPhotoFile = 'national_id_photo.jpg'),
          ),
          const SizedBox(height: 16),
          _uploadTile(
            label: 'Upload CV',
            icon: Icons.description_outlined,
            file: _cvFile,
            onTap: () => setState(() => _cvFile = 'cv_document.pdf'),
          ),
          if (_error1 != null) _errorText(_error1!),
          const SizedBox(height: 32),
          _primaryBtn('Continue', _next),
        ],
      ),
    );
  }

  // ── Step 2: Face Video ───────────────────────────────────────────────────

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CAREGIVER', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Face Verification', style: SovaTheme.textTheme.displayMedium),
          Text('Step 3 of 3',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            'Record a 10–15 second video of your face for identity verification.',
            style: TextStyle(color: SovaColors.sage, height: 1.5),
          ),
          const Spacer(),
          Center(child: _videoRecorder()),
          const Spacer(),
          _primaryBtn(
            _loading ? 'Submitting...' : 'Submit Application',
            _loading ? null : _next,
            color: _videoRecorded ? SovaColors.navy : SovaColors.sensorNeutral,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Step 3: Done ─────────────────────────────────────────────────────────

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
                color: SovaColors.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: SovaColors.success, size: 56),
            ).animate().scale(delay: 200.ms),
            const SizedBox(height: 32),
            Text('Application Submitted!',
                style: SovaTheme.textTheme.displayMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Your CV is under review. You can use the app while your credentials are being verified.',
              style: TextStyle(color: SovaColors.sage, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            _primaryBtn('Enter App', () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const CaregiverWrapper()),
                (_) => false,
              );
            }),
          ],
        ).animate().fadeIn(delay: 100.ms),
      ),
    );
  }

  // ── Video Recorder Widget ────────────────────────────────────────────────

  Widget _videoRecorder() {
    if (_videoRecorded) {
      return Column(children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: SovaColors.success.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle,
              color: SovaColors.success, size: 72),
        ).animate().scale(),
        const SizedBox(height: 16),
        const Text('Video Captured!',
            style: TextStyle(
                color: SovaColors.success,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        TextButton(
          onPressed: () => setState(() => _videoRecorded = false),
          child:
              const Text('Re-record', style: TextStyle(color: SovaColors.sage)),
        ),
      ]);
    }
    if (_recording) {
      return Column(children: [
        Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 180,
            height: 180,
            child: CircularProgressIndicator(
              value: _countdown / 13,
              strokeWidth: 4,
              backgroundColor: SovaColors.sensorNeutral,
              valueColor: const AlwaysStoppedAnimation(SovaColors.coral),
            ),
          ),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: SovaColors.coral.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.fiber_manual_record,
                  color: SovaColors.coral, size: 20),
              Text(
                '$_countdown',
                style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: SovaColors.charcoal),
              ),
            ]),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.03, duration: 500.ms),
        ]),
        const SizedBox(height: 16),
        const Text('Recording...', style: TextStyle(color: SovaColors.coral)),
      ]);
    }
    return Column(children: [
      GestureDetector(
        onTap: _startRecording,
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: SovaColors.navy.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
                color: SovaColors.navy.withValues(alpha: 0.3), width: 2),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.videocam_outlined,
                size: 42, color: SovaColors.navy.withValues(alpha: 0.7)),
            const SizedBox(height: 8),
            Text(
              'Tap to Record',
              style: TextStyle(
                  color: SovaColors.navy.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text('10–15 second video',
          style: TextStyle(color: SovaColors.sage, fontSize: 13)),
    ]);
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

  Widget _uploadTile({
    required String label,
    required IconData icon,
    required String? file,
    required VoidCallback onTap,
  }) {
    final uploaded = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: uploaded
              ? SovaColors.success.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: uploaded
                ? SovaColors.success.withValues(alpha: 0.4)
                : SovaColors.sensorNeutral,
            width: 1.5,
          ),
        ),
        child: Row(children: [
          Icon(uploaded ? Icons.check_circle : icon,
              color: uploaded ? SovaColors.success : SovaColors.sage),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              uploaded ? file : 'Tap to upload $label',
              style: TextStyle(
                color: uploaded ? SovaColors.success : SovaColors.sage,
                fontWeight: uploaded ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (!uploaded) Icon(Icons.upload_outlined, color: SovaColors.sage),
        ]),
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
