import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../models/user_models.dart';
import '../../services/mock_service.dart';
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
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _passVisible = false;
  String? _error0;

  // Step 1 – Your Face Video
  bool _myVideoRecorded = false;
  bool _myRecording = false;
  int _myCountdown = 13;

  // Step 2 – Patient Info
  final _patientNameCtrl = TextEditingController();
  String? _proofFile;
  bool _patientVideoRecorded = false;
  bool _patientRecording = false;
  int _patientCountdown = 13;
  String? _error2;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _patientNameCtrl.dispose();
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
    }
    if (_step == 2) {
      if (!_validateStep2()) return;
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

  bool _validateStep2() {
    if (_patientNameCtrl.text.trim().isEmpty) {
      setState(() => _error2 = 'Please enter the patient\'s name');
      return false;
    }
    if (!_patientVideoRecorded) {
      setState(() => _error2 = 'Please record the patient\'s face video');
      return false;
    }
    setState(() => _error2 = null);
    return true;
  }

  Future<void> _startMyRecording() async {
    setState(() {
      _myRecording = true;
      _myCountdown = 13;
    });
    for (int i = 13; i >= 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _myCountdown = i);
    }
    setState(() {
      _myRecording = false;
      _myVideoRecorded = true;
    });
  }

  Future<void> _startPatientRecording() async {
    setState(() {
      _patientRecording = true;
      _patientCountdown = 13;
    });
    for (int i = 13; i >= 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _patientCountdown = i);
    }
    setState(() {
      _patientRecording = false;
      _patientVideoRecorded = true;
    });
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final user = await MockService.instance.signupRelative(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      patientName: _patientNameCtrl.text.trim(),
      proofOfRelation: _proofFile,
    );
    AppState.currentUser.value = user;
    AppState.userRole.value = UserRole.relative;
    AppState.caregiverName.value = user.name;
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

  // ── Step 1: Your Face Video ──────────────────────────────────────────────

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RELATIVE', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Your Face Video', style: SovaTheme.textTheme.displayMedium),
          Text('Step 2 of 3',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            'Record a 10–15 second video of your face for identity verification.',
            style: TextStyle(color: SovaColors.sage, height: 1.5),
          ),
          const Spacer(),
          Center(
              child: _videoRecorder(
            recorded: _myVideoRecorded,
            recording: _myRecording,
            countdown: _myCountdown,
            onRecord: _startMyRecording,
            onReRecord: () => setState(() => _myVideoRecorded = false),
            accentColor: SovaColors.coral,
          )),
          const Spacer(),
          _primaryBtn('Continue', _next,
              color: _myVideoRecorded ? SovaColors.coral : SovaColors.sensorNeutral),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Step 2: Patient Info ─────────────────────────────────────────────────

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RELATIVE', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Patient Information', style: SovaTheme.textTheme.displayMedium),
          Text('Step 3 of 3',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            'Tell us about the patient you will be monitoring.',
            style: TextStyle(color: SovaColors.sage, height: 1.5),
          ),
          const SizedBox(height: 28),
          _field(_patientNameCtrl, 'Patient\'s Full Name', Icons.person_outline),
          const SizedBox(height: 16),
          _uploadTile(
            label: 'Proof of Relation (document)',
            icon: Icons.folder_open_outlined,
            file: _proofFile,
            onTap: () => setState(() => _proofFile = 'proof_of_relation.pdf'),
          ),
          const SizedBox(height: 24),
          Text(
            "Patient's Face Video",
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: SovaColors.charcoal),
          ),
          const SizedBox(height: 4),
          Text(
            'A 10–15 second video helps the system identify your patient.',
            style: TextStyle(color: SovaColors.sage, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Center(
            child: _videoRecorder(
              recorded: _patientVideoRecorded,
              recording: _patientRecording,
              countdown: _patientCountdown,
              onRecord: _startPatientRecording,
              onReRecord: () => setState(() => _patientVideoRecorded = false),
              accentColor: SovaColors.navy,
            ),
          ),
          if (_error2 != null) _errorText(_error2!),
          const SizedBox(height: 32),
          _primaryBtn(
            _loading ? 'Creating Account...' : 'Create Account',
            _loading ? null : _next,
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
                color: SovaColors.coral.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite,
                  color: SovaColors.coral, size: 52),
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

  // ── Video Recorder ───────────────────────────────────────────────────────

  Widget _videoRecorder({
    required bool recorded,
    required bool recording,
    required int countdown,
    required VoidCallback onRecord,
    required VoidCallback onReRecord,
    required Color accentColor,
  }) {
    if (recorded) {
      return Column(children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: SovaColors.success.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle,
              color: SovaColors.success, size: 64),
        ).animate().scale(),
        const SizedBox(height: 16),
        const Text('Video Captured!',
            style: TextStyle(
                color: SovaColors.success,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        TextButton(
          onPressed: onReRecord,
          child:
              const Text('Re-record', style: TextStyle(color: SovaColors.sage)),
        ),
      ]);
    }
    if (recording) {
      return Column(children: [
        Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 180,
            height: 180,
            child: CircularProgressIndicator(
              value: countdown / 13,
              strokeWidth: 4,
              backgroundColor: SovaColors.sensorNeutral,
              valueColor: AlwaysStoppedAnimation(accentColor),
            ),
          ),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fiber_manual_record,
                      color: accentColor, size: 20),
                  Text('$countdown',
                      style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: SovaColors.charcoal)),
                ]),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.03, duration: 500.ms),
        ]),
        const SizedBox(height: 16),
        Text('Recording...', style: TextStyle(color: accentColor)),
      ]);
    }
    return Column(children: [
      GestureDetector(
        onTap: onRecord,
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
                color: accentColor.withValues(alpha: 0.3), width: 2),
          ),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_outlined,
                    size: 38, color: accentColor.withValues(alpha: 0.7)),
                const SizedBox(height: 8),
                Text('Tap to Record',
                    style: TextStyle(
                        color: accentColor.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
        ),
      ),
      const SizedBox(height: 10),
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
